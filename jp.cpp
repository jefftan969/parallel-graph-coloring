#include "graph.h"

#include <iostream>
#include <string>
#include <vector>
#include <algorithm>
#include <stdlib.h>
#include <omp.h>

std::vector<int> jpColoring(Graph& graph) {
    int numVertices = graph.getNumVertices();
    int currentColor = 0;

    // Create the vector in which the final colors will be stored
    // Element at index i will be the color of vertex i
    std::vector<int> coloring(numVertices, -1);

    // Keep a worklist, the set of vertices that need to be considered
    std::vector<int> W;
    for(int i = 0; i < numVertices; i++) {
        W.push_back(i);
    }

    while(!W.empty()) {
        // Assign random weights to each vertex
        std::vector<int> weights(numVertices);
        for (int i = 0; i < numVertices; i++) {
            weights.at(i) = rand();
        }

        // Initialize the independent set of vertices
        std::vector<int> S(0);

        // Add vertices to the independent set
        for (int j = 0; j < (int) W.size(); j++) {
            int vertex = W.at(j);
            bool flag = true;
            const std::vector<int>& neighbors = graph.getNeighbors(vertex);
            for (int j = 0; j < (int) neighbors.size(); j++) {
                int neighbor = neighbors.at(j);
                if (weights.at(vertex) <= weights.at(neighbor)) {
                    flag = false;
                }
            }

            if (flag) {
                S.push_back(vertex);
            }
        }

        // Color the independent set
        for (int j = 0; j < (int) S.size(); j++) {
            int vertex = S.at(j);
            coloring.at(vertex) = currentColor;
        }

        // Update the working set and color
        if (!S.empty()) {
            std::vector<int> newW;
            std::set_difference(W.begin(), W.end(), S.begin(), S.end(), 
                                std::inserter(newW, newW.end()));
            W = newW;
            currentColor++;
        }
    }
    return coloring;
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        std::cout << "Usage: " << argv[0] << " [in_filename]\n";
        exit(0);
    }

    const std::string in_filename = argv[1];
    Graph graph = Graph(in_filename);
    
    std::vector<int> coloring = jpColoring(graph);
    bool validColoring = checkColoring(graph, coloring);

    if (validColoring) printColoring(coloring);
    else std::cout << "Invalid coloring\n";

    return 0;
}
