#include "driver/language_server.h"
#include "driver/options.h"
#include <exception>
#include <iostream>
#include <string_view>

int main(int argc, char **argv) {
  if (argc == 2 && std::string_view(argv[1]) == "--version") {
    std::cout << "mettle " METTLE_VERSION
                 " (I02 scalar source compiler; I03 ownership subset)\n";
    return 0;
  }
  if (argc == 2 && (std::string_view(argv[1]) == "--help" ||
                    std::string_view(argv[1]) == "-h")) {
    mettle::driver::usage();
    return 0;
  }
  if (argc >= 2 && std::string_view(argv[1]) == "lsp") {
    int status = mettle::driver::languageServer(argc, argv);
    if (status == 2)
      std::cerr << "mettle: invalid arguments; use --help\n";
    return status;
  }
  auto options = mettle::driver::options(argc, argv);
  if (!options) {
    std::cerr << "mettle: invalid arguments; use --help\n";
    return 2;
  }
  try {
    return mettle::driver::run(*options);
  } catch (const std::exception &error) {
    std::cerr << "mettle: error[internal]: " << error.what() << '\n';
    return 1;
  }
}
