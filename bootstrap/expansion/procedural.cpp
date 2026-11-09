#include "expansion/procedural.h"
#include <algorithm>
#include <sstream>

namespace mettle::expansion {
namespace {
bool variableName(const std::string &name) {
  return !name.empty() && !(name[0] >= '0' && name[0] <= '9') &&
         std::all_of(name.begin(), name.end(), [](char c) {
           return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                  (c >= '0' && c <= '9') || c == '_';
         });
}
} // namespace

std::string escapeField(std::string_view text) {
  std::string result;
  for (char c : text) {
    if (c == '\\')
      result += "\\\\";
    else if (c == '\n')
      result += "\\n";
    else if (c == '\r')
      result += "\\r";
    else
      result += c;
  }
  return result;
}

std::string unescapeField(std::string_view text) {
  std::string result;
  for (std::size_t i = 0; i < text.size(); ++i) {
    if (text[i] != '\\' || i + 1 == text.size()) {
      result += text[i];
      continue;
    }
    char next = text[++i];
    result += next == 'n' ? '\n' : next == 'r' ? '\r' : next;
  }
  return result;
}

std::string encodeRequest(const std::string &name,
                          const std::vector<ProcedureToken> &tokens) {
  std::string text = "mettle-macro " + std::to_string(procedureApiMajor) + "." +
                     std::to_string(procedureApiMinor) + "\nname " + name +
                     "\n";
  for (const auto &token : tokens)
    text += "tok " + token.kind + (token.spaced ? " 1 " : " 0 ") +
            escapeField(token.text) + "\n";
  return text;
}

ProcedureResponse parseResponse(const std::string &output) {
  ProcedureResponse response;
  std::istringstream lines(output);
  for (std::string line; std::getline(lines, line);) {
    if (!line.empty() && line.back() == '\r')
      line.pop_back();
    if (line.rfind("mettle:", 0) != 0)
      continue;
    auto body = line.substr(7);
    auto split = body.find('=');
    auto key = body.substr(0, split);
    auto value =
        split == std::string::npos ? std::string() : body.substr(split + 1);
    if (key == "reproducible" && split == std::string::npos)
      response.reproducible = true;
    else if (key == "text" && split != std::string::npos)
      response.text += unescapeField(value);
    else if (key == "error" && split != std::string::npos)
      response.errors.push_back(unescapeField(value));
    else if (key == "rerun-if-changed" && !value.empty())
      response.files.push_back(value);
    else if (key == "rerun-if-env-changed" && variableName(value))
      response.variables.push_back(value);
    else {
      response.fault = "unknown or malformed response line '" + line + "'";
      return response;
    }
  }
  return response;
}
} // namespace mettle::expansion
