#include <iostream>
#include <string>
#include <vector>
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <omp.h>

#include "graph.h"

// Note: This code performs graph coloring by using CUDA for NUM_CUDA_ITERS, before switching to a
// sequential algorithm to color the remaining vertices. Since the remaining vertices have all
// participated in multiple conflicts, it is likely that they are highly interconnected and more
// difficult to color, so a sequential implementation would avoid the contention of a massively
// parallel GPU implementation.
#define COLOR_MASK_SIZE 500
#define BLOCK_SIZE 128
#define NUM_CUDA_ITERS 16

#define DEBUG
#ifdef DEBUG
#define cudaCheckError(ans) cudaAssert((ans), __FILE__, __LINE__);
inline void cudaAssert(cudaError_t code, const char *file, int line, bool abort=true) {
    if(code != cudaSuccess) {
        fprintf(stderr, "CUDA Error: %s at %s:%d\n", cudaGetErrorString(code), file, line);
        if(abort) {
            exit(code);
        }
    }
}
#else
#define cudaCheckError(ans) ans
#endif

// Stores all data structures allocated on CUDA device
struct cudaContext {
    int numVertices;
    int numEdges;
    int blockSize;
    int *vertices;  // Length numVertices+1 - List of graph vertices, in CSR representation
    int *neighbors; // Length 2*numEdges    - List of vertex neighbors, in CSR representation
    int *worklist;  // Length numVertices   - Boolean array indicating whether each vertex is in worklist
    int *coloring;  // Length numVertices   - Integer array indicating color of each vertex
    int *worklistEmptyFlag; // Boolean flag indicating whether the worklist is empty
};

/**
 * @brief Speculatively color vertices in parallel, allowing conflicts which will be resolved later
 * @param[in] context All data structures allocated on CUDA device
 */
__global__ void kernelSpeculate(struct cudaContext context) {
    int v = blockIdx.x * BLOCK_SIZE + threadIdx.x;
    int colorMask[COLOR_MASK_SIZE];

    int numVertices = context.numVertices;
    const int *vertices = context.vertices;
    const int *neighbors = context.neighbors;
    int *worklist = context.worklist;
    int *coloring = context.coloring;

    if(v < numVertices && worklist[v]) {
        // Determine colors of all vertex neighbors
        for(int i = vertices[v]; i < vertices[v+1]; i++) {
            int w = neighbors[i];
            colorMask[coloring[w]] = v;
        }
        // Color each vertex with the minimal acceptable color
        for(int i = 0; i < COLOR_MASK_SIZE; i++) {
            if(colorMask[i] != v) {
                coloring[v] = i;
                break;
            }
        }
    }
}

/**
 * @brief Detect conflicts from speculative coloring phase, and remove valid vertices from worklist
 * @param[in] context All data structures allocated on CUDA device
 */
__global__ void kernelResolveConflicts(struct cudaContext context) {
    int v = blockIdx.x * BLOCK_SIZE + threadIdx.x;

    int numVertices = context.numVertices;
    const int *vertices = context.vertices;
    const int *neighbors = context.neighbors;
    int *worklist = context.worklist;
    int *coloring = context.coloring;
    int *worklistEmptyFlag = context.worklistEmptyFlag;

    if(v < numVertices && worklist[v]) {
        // Resolve conflicts between neighbors and determine the remaining worklist
        for(int i = vertices[v]; i < vertices[v+1]; i++) {
            int w = neighbors[i];
            if((v < w) && (coloring[v] == coloring[w])) {
                // Indicate that worklist is not empty and elements still remain
                *worklistEmptyFlag = 0;
                return;
            }
        }
        worklist[v] = 0;
    }
}

/**
 * @brief Copy graph representation to CUDA device and allocate all necessary data structures
 * @param[in] graph The graph to color
 * @return context A cudaContext struct containing all device data structures
 */
struct cudaContext setup(const Graph &graph) {
    int numVertices = graph.getNumVertices();
    int numEdges = graph.getNumEdges();
    const int *vertices = graph.getCSRVertices();
    const int *neighbors = graph.getCSRNeighbors();

    // Initialize data structures
    struct cudaContext context;
    context.numVertices = numVertices;
    context.numEdges = numEdges;
    cudaMalloc(&context.vertices, sizeof(int) * (numVertices + 1));
    cudaMalloc(&context.neighbors, sizeof(int) * 2 * numEdges);
    cudaMalloc(&context.worklist, sizeof(int) * numVertices);
    cudaMalloc(&context.coloring, sizeof(int) * numVertices);
    cudaMalloc(&context.worklistEmptyFlag, sizeof(int));
   
    // Note that cudaMemset sets values per byte, so 0x01 => 0x01010101 = 16843009
    cudaMemcpy(context.vertices, vertices, sizeof(int) * (numVertices + 1), cudaMemcpyHostToDevice);
    cudaMemcpy(context.neighbors, neighbors, sizeof(int) * 2 * numEdges, cudaMemcpyHostToDevice);
    cudaMemset(context.worklist, 0x01, sizeof(int) * numVertices);
    cudaMemset(context.coloring, 0x00, sizeof(int) * numVertices);
    cudaMemset(context.worklistEmptyFlag, 0x00, sizeof(int));

    return context;
}

/**
 * @brief Frees all data structures in the given CUDA context
 * @param[in] context The CUDA context to free
 */
void freeCudaContext(struct cudaContext context) {
    cudaFree(context.vertices);
    cudaFree(context.neighbors);
    cudaFree(context.worklist);
    cudaFree(context.coloring);
    cudaFree(context.worklistEmptyFlag);
}

/**
 * @brief Performs graph coloring using the GM algorithm
 * @param[in] context A cudaContext sturct containing all device data structures
 * @return coloring The outputted coloring (which the user is responsible for freeing)
 */
const int *gmColoring(const Graph &graph, struct cudaContext context) {
    int numVertices = context.numVertices;
    const int *vertices = graph.getCSRVertices();
    const int *neighbors = graph.getCSRNeighbors();

    // Define kernel size and device flags
    dim3 blockDim(BLOCK_SIZE);
    dim3 gridDim((numVertices + BLOCK_SIZE - 1) / BLOCK_SIZE);
    int worklistEmptyFlag = 0;

    // Loop until worklist is empty, or until NUM_CUDA_ITERS have been performed
    for(int iter = 0; iter < NUM_CUDA_ITERS && !worklistEmptyFlag; iter++) {
        // Determine which colors are permissible for each vertex
        kernelSpeculate<<<gridDim, blockDim>>>(context);
        cudaDeviceSynchronize();

        // Resolve conflicts and determine the remaining worklist
        cudaMemset(context.worklistEmptyFlag, 0x01, sizeof(int));
        kernelResolveConflicts<<<gridDim, blockDim>>>(context);
        cudaMemcpy(&worklistEmptyFlag, context.worklistEmptyFlag, sizeof(int), cudaMemcpyDeviceToHost);
        cudaDeviceSynchronize();
    }

    // Retrieve worklist and coloring from device
    int *worklist = new int[numVertices];
    int *coloring = new int[numVertices];
    int *colorMask = new int[numVertices];
    cudaMemcpy(worklist, context.worklist, sizeof(int) * numVertices, cudaMemcpyDeviceToHost);
    cudaMemcpy(coloring, context.coloring, sizeof(int) * numVertices, cudaMemcpyDeviceToHost);

    // Represent worklist as a vector in compressed form
    std::vector<int> W;
    for(int v = 0; v < numVertices; v++) {
        if(worklist[v]) {
            W.push_back(v);
        }
    }

    // Use sequential GM algorithm to color remaining hard-to-color vertices
    while(!W.empty()) {
        // Determine which colors are permissible for each vertex
        for(int i = 0; i < (int)W.size(); i++) {
            int v = W[i];
            for(int j = vertices[v]; j < vertices[v+1]; j++) {
                int w = neighbors[j];
                colorMask[coloring[w]] = v;
            }
            for(int j = 0; j < numVertices; j++) {
                if(colorMask[j] != v) {
                    coloring[v] = j;
                    break;
                }
            }
        }

        // Initialize the remaining worklist
        std::vector<int> R;
        for(int i = 0; i < (int)W.size(); i++) {
            int v = W[i];
            for(int j = vertices[v]; j < vertices[v+1]; j++) {
                int w = neighbors[j];
                if((v < w) && (coloring[v] == coloring[w])) {
                    R.push_back(v);
                }
            }
        }

        // Update current worklist
        std::swap(W, R);
    }

    delete worklist;
    delete colorMask;
    return coloring;
}

int main(int argc, char *argv[]) {
    if(argc < 2) {
        std::cout << "Usage: " << argv[0] << " [in_filename]\n";
        exit(-1);
    }
    const std::string in_filename = argv[1];
    Graph graph = Graph(in_filename);
    struct cudaContext context = setup(graph);

    auto t1 = getTime();
    const int *coloring = gmColoring(graph, context);
    auto t2 = getTime();
    std::cout << "Time: " << getMillis(t1, t2) << "ms\n";

    int numColors = numColorsUsed(coloring, graph.getNumVertices());
    std::cout << "Colors used: " << numColors << "\n";

    bool validColoring = checkColoring(graph, coloring);
    if(!validColoring) {
        std::cout << "Invalid coloring\n";
    }

    freeCudaContext(context);
    delete coloring;
    return 0;
}
