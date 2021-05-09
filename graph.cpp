#include <chrono>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>
#include <stdlib.h>

#include "graph.h"

/**
 * @brief Constructs a graph from the given input file.
 *        The first line of the file is the number of vertices in the graph,
 *        and the remaining lines "<v1> <v2>" denote edges in the graph,
 *        where v1 and v2 are the vertices in the edge separated by a space.
 *        Graphs are represented as adjacency lists using a vector of vectors.
 * @param[in] filename Input file containing the graph
 */
Graph::Graph(const std::string &filename) :
    filename_(filename)
{
    // Try to open file
    std::ifstream file(filename.c_str());
    if(!file.is_open()) {
        std::cerr << "Error: File '" << filename << "' does not exist\n";
        exit(-1);
    }

    if(filename.substr(filename.length() - 4) == ".col") {
        // Interpret graph as DIMACS standard format
        parseDimacs(file);
    } else if(filename.substr(filename.length() - 6) == ".col.b") {
        // Interpret graph as DIMACS binary format
        parseDimacsBinary(file);
    } else if(filename.substr(filename.length() - 4) == ".txt") {
        // Interpret graph as edge list format
        parseEdgeList(file);
    } else if(filename.substr(filename.length() - 4) == ".mtx") {
        // Interpret graph as Matrix Market format
        parseMatrixMarket(file);
    } else {
        std::cerr << "Error: File '" << filename << "' has an unknown format\n";
        exit(-1);
    }
}

/**
 * @brief Parse graph representation as DIMACS edge list format
 * @param[in] file Input file
 */
void Graph::parseDimacs(std::istream &file) {
    std::string line;
    while(std::getline(file, line)) {
        char linetype;
        std::stringstream ss(line);
        ss >> linetype;

        if(linetype == 'e') {
            // Read edge, note that DIMACS edge list format is 1-indexed
            int v1, v2;
            ss >> v1 >> v2;
            graph_.at(v1-1).push_back(v2-1);
            graph_.at(v2-1).push_back(v1-1);

        } else if(linetype == 'p') {
            // Read number of vertices
            std::string filetype;
            ss >> filetype;
            if(filetype != "edge") {
                std::cerr << "Error: File is not in DIMACS edge list format\n";
                exit(-1);
            }

            ss >> numVertices_;
            graph_.resize(numVertices_);
        }
    }
}

/**
 * @brief Parse graph representation as DIMACS binary format
 * @param[in] file Input file
 */
void Graph::parseDimacsBinary(std::istream &file) {
    std::string line;

    // Read preamble
    std::getline(file, line);
    while(std::getline(file, line)) {
        char linetype;
        std::stringstream ss(line);
        ss >> linetype;

        if(linetype == 'p') {
            // Read number of vertices
            std::string filetype;
            ss >> filetype;
            if(filetype != "edge") {
                std::cerr << "Error: File is not in DIMACS binary format\n";
                exit(-1);
            }

            ss >> numVertices_;
            graph_.resize(numVertices_);
            break;
        }
    }

    // Read rows of adjacency matrix, and add edges to graph data structure
    char *adjacencyRow = new char[numVertices_/8 + 1];
    for(int i = 0; i < numVertices_; i++) {
        file.read(adjacencyRow, i/8 + 1);

        for(int j = 0; j <= i; j++) {
            int bit = 0x07 - (j & 0x07);
            int byte = j >> 3;
            char mask = 0x01 << bit;

            if((adjacencyRow[byte] & mask) == mask) {
                graph_.at(i).push_back(j);
                graph_.at(j).push_back(i);
            }
        }
    }
}

/**
 * @brief Parse graph representation as Matrix Market adjacency matrix format
 * @param[in] file Input file
 */
void Graph::parseMatrixMarket(std::istream &file) {
    // TODO implement matrix market parsing
}

/**
 * @brief Parse graph representation as custom edge list format
 * @param[in] file Input file
 */
void Graph::parseEdgeList(std::istream &file) {
    // First line contains number of vertices, subsequent lines each denote an edge
    std::string line;
    std::getline(file, line);
    std::stringstream ss(line);

    ss >> numVertices_;
    graph_.resize(numVertices_);

    while(std::getline(file, line)) {
        std::stringstream ss(line);
        
        int v1, v2;
        ss >> v1 >> v2;
        graph_.at(v1).push_back(v2);
        graph_.at(v2).push_back(v1);
    }
}

/**
 * @brief Returns the number of vertices in the graph
 */
int Graph::getNumVertices(void) const {
    return numVertices_;
}

/**
 * @brief Returns a vector of neighbors for the given vertex
 */
const std::vector<int>& Graph::getNeighbors(int vertex) const {
    return graph_.at(vertex);
}

/**
 * @brief Prints the adjacency list of the current graph
 */
void Graph::print(void) const {
    std::cout << "Graph " << filename_ << ": \n";
    for(int v = 0; v < numVertices_; v++) {
        std::cout << v << ": ";
        for(int w : getNeighbors(v)) {
            std::cout << w << " ";
        }
        std::cout << "\n";
    }
}

/**
 * @brief Prints a given vertex coloring
 * @param[in] coloring A vertex indexed vector, storing the color of each vertex
 */
void printColoring(const std::vector<int> &coloring) {
    std::cout << "Coloring: \n";
    for(size_t v = 0; v < coloring.size(); v++) {
        std::cout << v << ": " << coloring.at(v) << "\n";
    }
}

/**
 * @brief Given a graph, checks whether the given vertex coloring is correct,
 *        printing out any invalid edges where both vertices have the same color
 * @param[in] graph The graph to check against
 * @param[in] coloring A vertex indexed vector, storing the color of each vertex
 */
bool checkColoring(const Graph &graph, const std::vector<int> &coloring) {
    bool isValid = true;
    for(int v = 0; v < graph.getNumVertices(); v++) {
        for(int w : graph.getNeighbors(v)) {
            if((v < w) && (coloring.at(v) == coloring.at(w))) {
                isValid = false;
                std::cout << "Edge (" << v << ", " << w << ") invalid: "
                          << "color[" << v << "] = color[" << w << "] = " << coloring.at(v) << "\n";
            }
        }
    }
    return isValid;
}
