# first-zig

This repository contains a few mini-projects to learn Zig (for fun and just for learning purposes)

Index
1. hello-world: classic hello world example
    * Here my purpose was to understand the CLI params, see how the compiler works, and the testing module. The source code present in this folder is a minimal bootstrap project because the aim was to understand the basic structure of a Zig project
2. css-parser: a minimal CSS parser
    * For this mini-project, I learned how to read a CSS file, how to create a pseudo-AST, and then parse it into a JSON file. For future versions, I think PostCSS or other alternatives can handle CSS abstraction better by creating a real AST instead of keyword-specific detection. Also, to get a minimal pseudo-AST I had to delete the comments before going through the final CSS, but in a realistic case, the comments are part of the original definition that we should keep in the final AST
