#include "driver/cache.h"
#include "driver/options.h"
#include "driver/session.h"
#include "lsp/json.h"
#include "packages/sha256.h"
#include <iostream>

#ifdef __linux__
#include <algorithm>
#include <array>
#include <cerrno>
#include <csignal>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <filesystem>
#include <limits>
#include <poll.h>
#include <span>
#include <stdexcept>
#include <string_view>
#include <sys/eventfd.h>
#include <sys/file.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <system_error>
#include <thread>
#include <unistd.h>
#include <utility>

extern char **environ;
#endif

namespace mettle::driver {
#ifdef __linux__
namespace {
class Descriptor {
public:
  explicit Descriptor(int value = -1) : value(value) {}
  ~Descriptor() {
    if (value >= 0)
      ::close(value);
  }
  Descriptor(const Descriptor &) = delete;
  Descriptor &operator=(const Descriptor &) = delete;
  Descriptor(Descriptor &&other) noexcept
      : value(std::exchange(other.value, -1)) {}
  Descriptor &operator=(Descriptor &&other) noexcept {
    if (value >= 0)
      ::close(value);
    value = std::exchange(other.value, -1);
    return *this;
  }
  int get() const { return value; }

private:
  int value;
};

[[noreturn]] void systemFailure(const char *action) {
  throw std::system_error(errno, std::generic_category(), action);
}

class RequestLifetime {
public:
  explicit RequestLifetime(int socket) : finished(::eventfd(0, EFD_CLOEXEC)) {
    if (finished.get() < 0)
      systemFailure("cannot observe resident compiler cancellation");
    observer = std::thread([this, socket] {
      std::array<pollfd, 2> events{
          {{finished.get(), POLLIN, 0}, {socket, POLLRDHUP, 0}}};
      int status;
      do {
        status = ::poll(events.data(), events.size(), -1);
      } while (status < 0 && errno == EINTR);
      if (status < 0 || (!events[0].revents && events[1].revents))
        ::kill(0, SIGINT);
    });
  }
  ~RequestLifetime() {
    std::uint64_t complete = 1;
    ssize_t size;
    do {
      size = ::write(finished.get(), &complete, sizeof(complete));
    } while (size < 0 && errno == EINTR);
    if (size != sizeof(complete))
      std::terminate();
    observer.join();
  }
  RequestLifetime(const RequestLifetime &) = delete;
  RequestLifetime &operator=(const RequestLifetime &) = delete;

private:
  Descriptor finished;
  std::thread observer;
};

std::string encodeBytes(std::string_view text) {
  constexpr char digits[] = "0123456789abcdef";
  if (text.size() > std::string{}.max_size() / 2)
    throw std::length_error("resident message exceeds string representation");
  std::string result(text.size() * 2, '\0');
  for (std::size_t i = 0; i < text.size(); ++i) {
    auto byte = static_cast<unsigned char>(text[i]);
    result[i * 2] = digits[byte >> 4];
    result[i * 2 + 1] = digits[byte & 15];
  }
  return result;
}

std::string decodeBytes(const lsp::Json *value) {
  auto text = value ? value->asString() : nullptr;
  if (!text || text->size() % 2)
    throw std::runtime_error("invalid resident byte string");
  auto digit = [](char value) -> unsigned {
    if (value >= '0' && value <= '9')
      return value - '0';
    if (value >= 'a' && value <= 'f')
      return value - 'a' + 10;
    throw std::runtime_error("invalid resident byte string");
  };
  std::string result(text->size() / 2, '\0');
  for (std::size_t i = 0; i < result.size(); ++i)
    result[i] = static_cast<char>((digit((*text)[i * 2]) << 4) |
                                  digit((*text)[i * 2 + 1]));
  return result;
}

void writeBytes(int socket, std::string_view bytes) {
  while (!bytes.empty()) {
    auto size = ::send(socket, bytes.data(), bytes.size(), MSG_NOSIGNAL);
    if (size < 0 && errno == EINTR)
      continue;
    if (!size)
      throw std::runtime_error("resident compiler connection stopped writing");
    if (size < 0)
      systemFailure("cannot write resident compiler message");
    bytes.remove_prefix(static_cast<std::size_t>(size));
  }
}

void readBytes(int socket, std::span<char> bytes) {
  while (!bytes.empty()) {
    auto size = ::recv(socket, bytes.data(), bytes.size(), 0);
    if (size < 0 && errno == EINTR)
      continue;
    if (size <= 0) {
      if (!size)
        throw std::runtime_error("resident compiler disconnected");
      systemFailure("cannot read resident compiler message");
    }
    bytes = bytes.subspan(static_cast<std::size_t>(size));
  }
}

void writeMessage(int socket, const lsp::Json &message) {
  auto bytes = message.dump();
  std::array<char, 8> length;
  for (unsigned i = 0; i < length.size(); ++i)
    length[i] = static_cast<char>(std::uint64_t(bytes.size()) >> (i * 8));
  writeBytes(socket, {length.data(), length.size()});
  writeBytes(socket, bytes);
}

lsp::Json readMessage(int socket, std::size_t limit) {
  std::array<char, 8> length;
  readBytes(socket, length);
  std::uint64_t size = 0;
  for (unsigned i = 0; i < length.size(); ++i)
    size |= std::uint64_t(static_cast<unsigned char>(length[i])) << (i * 8);
  if (size > limit)
    throw std::runtime_error("resident message exceeds its representation");
  std::string bytes(static_cast<std::size_t>(size), '\0');
  readBytes(socket, std::span(bytes));
  auto message = lsp::Json::parse(bytes);
  if (!message || message->type() != lsp::Json::Type::Object)
    throw std::runtime_error("invalid resident compiler message");
  return std::move(*message);
}

void validatePeer(int socket) {
  ucred credential{};
  socklen_t size = sizeof(credential);
  if (::getsockopt(socket, SOL_SOCKET, SO_PEERCRED, &credential, &size))
    systemFailure("cannot authenticate resident compiler peer");
  if (size != sizeof(credential) || credential.uid != ::getuid())
    throw std::runtime_error("resident compiler peer has a different owner");
}

struct Endpoint {
  sockaddr_un address{};
  socklen_t length = 0;
  std::string name, directory;
};

Endpoint endpoint(const Options &options) {
  namespace fs = std::filesystem;
  fs::path cache = options.cacheDir;
  if (cache.empty()) {
    if (auto value = std::getenv("METTLE_CACHE_DIR"); value && *value)
      cache = value;
    else if (auto value = std::getenv("XDG_CACHE_HOME"); value && *value)
      cache = fs::path(value) / "mettle";
    else if (auto value = std::getenv("HOME"); value && *value)
      cache = fs::path(value) / ".cache" / "mettle";
  }
  packages::Sha256 hash;
  for (const auto &field :
       {std::string("mettle-resident-1"), compilerIdentity(),
        fs::current_path().generic_string(),
        cache.empty()
            ? std::string{}
            : fs::absolute(cache).lexically_normal().generic_string()}) {
    hash.update(field);
    hash.update(std::string_view("\0", 1));
  }
  for (auto resource :
       {RLIMIT_CPU, RLIMIT_FSIZE, RLIMIT_DATA, RLIMIT_STACK, RLIMIT_CORE,
        RLIMIT_RSS, RLIMIT_NPROC, RLIMIT_NOFILE, RLIMIT_MEMLOCK, RLIMIT_AS,
        RLIMIT_LOCKS, RLIMIT_SIGPENDING, RLIMIT_MSGQUEUE, RLIMIT_NICE,
        RLIMIT_RTPRIO, RLIMIT_RTTIME}) {
    rlimit policy{};
    if (::getrlimit(resource, &policy))
      systemFailure("cannot inspect resident compiler resource policy");
    hash.update(std::to_string(policy.rlim_cur));
    hash.update(std::string_view("\0", 1));
    hash.update(std::to_string(policy.rlim_max));
    hash.update(std::string_view("\0", 1));
  }
  Endpoint result;
  result.name = hash.finish();
  result.directory = "/tmp/mettle-resident-" + std::to_string(::getuid());
  auto name = "mettle-" + std::to_string(::getuid()) + "-" + result.name;
  if (name.size() + 1 > sizeof(result.address.sun_path))
    throw std::length_error("resident socket name exceeds host representation");
  result.address.sun_family = AF_UNIX;
  std::memcpy(result.address.sun_path + 1, name.data(), name.size());
  result.length =
      static_cast<socklen_t>(offsetof(sockaddr_un, sun_path) + name.size() + 1);
  return result;
}

Descriptor connect(const Endpoint &endpoint) {
  Descriptor socket(::socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0));
  if (socket.get() < 0)
    systemFailure("cannot create resident compiler connection");
  int status;
  do {
    status = ::connect(socket.get(),
                       reinterpret_cast<const sockaddr *>(&endpoint.address),
                       endpoint.length);
  } while (status && errno == EINTR);
  if (status) {
    if (errno == ECONNREFUSED || errno == ENOENT)
      return Descriptor{};
    systemFailure("cannot connect to resident compiler");
  }
  validatePeer(socket.get());
  return socket;
}

Descriptor privateDirectory(const Endpoint &endpoint) {
  if (::mkdir(endpoint.directory.c_str(), 0700) && errno != EEXIST)
    systemFailure("cannot create resident compiler directory");
  Descriptor directory(::open(endpoint.directory.c_str(),
                              O_DIRECTORY | O_RDONLY | O_CLOEXEC | O_NOFOLLOW));
  if (directory.get() < 0)
    systemFailure("cannot open resident compiler directory");
  struct stat facts{};
  if (::fstat(directory.get(), &facts))
    systemFailure("cannot inspect resident compiler directory");
  if (facts.st_uid != ::getuid() || (facts.st_mode & 0777) != 0700)
    throw std::runtime_error("resident compiler directory is not private");
  return directory;
}

Descriptor privateFile(int directory, const std::string &name, int flags) {
  Descriptor file(::openat(directory, name.c_str(),
                           flags | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0600));
  if (file.get() < 0)
    systemFailure("cannot open resident compiler state file");
  struct stat facts{};
  if (::fstat(file.get(), &facts))
    systemFailure("cannot inspect resident compiler state file");
  if (!S_ISREG(facts.st_mode) || facts.st_uid != ::getuid() ||
      (facts.st_mode & 0777) != 0600 || facts.st_nlink != 1)
    throw std::runtime_error("resident compiler state file is not private");
  return file;
}

void serve(const Endpoint &endpoint, Descriptor &ready, int log) {
  if (::signal(SIGINT, SIG_DFL) == SIG_ERR)
    systemFailure("cannot install resident compiler cancellation");
  Descriptor input(::open("/dev/null", O_RDONLY | O_CLOEXEC));
  if (input.get() < 0 || ::dup2(input.get(), STDIN_FILENO) < 0 ||
      ::dup2(log, STDOUT_FILENO) < 0 || ::dup2(log, STDERR_FILENO) < 0)
    systemFailure("cannot detach resident compiler streams");
  Descriptor listener(::socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0));
  if (listener.get() < 0 ||
      ::bind(listener.get(),
             reinterpret_cast<const sockaddr *>(&endpoint.address),
             endpoint.length) ||
      ::listen(listener.get(), SOMAXCONN))
    systemFailure("cannot listen for resident compiler requests");
  const int success = 0;
  if (::write(ready.get(), &success, sizeof(success)) != sizeof(success))
    systemFailure("cannot publish resident compiler readiness");
  ready = Descriptor{};
  CompilationSession session;
  std::vector<std::string> environment;
  auto initialEnvironment = ::environ;
  std::vector<char *> environmentPointers;
  struct EnvironmentRestore {
    char **original;
    ~EnvironmentRestore() { ::environ = original; }
  } restore{initialEnvironment};
  bool environmentInstalled = false;
  const auto argumentBytes = ::sysconf(_SC_ARG_MAX);
  if (argumentBytes <= 0 || static_cast<unsigned long>(argumentBytes) >
                                std::numeric_limits<std::size_t>::max() / 4)
    throw std::runtime_error("cannot determine native argument representation");
  const auto requestLimit = static_cast<std::size_t>(argumentBytes) * 4;
  for (;;) {
    pollfd poller{listener.get(), POLLIN, 0};
    int activity;
    do {
      activity = ::poll(&poller, 1, 600000);
    } while (activity < 0 && errno == EINTR);
    if (!activity)
      return;
    if (activity < 0)
      systemFailure("cannot wait for resident compiler requests");
    Descriptor socket(
        ::accept4(listener.get(), nullptr, nullptr, SOCK_CLOEXEC));
    if (socket.get() < 0 && errno == EINTR)
      continue;
    if (socket.get() < 0)
      systemFailure("cannot accept resident compiler request");
    validatePeer(socket.get());
    timeval timeout{10, 0};
    if (::setsockopt(socket.get(), SOL_SOCKET, SO_RCVTIMEO, &timeout,
                     sizeof(timeout)) ||
        ::setsockopt(socket.get(), SOL_SOCKET, SO_SNDTIMEO, &timeout,
                     sizeof(timeout)))
      systemFailure("cannot bound resident compiler transport inactivity");
    auto request = readMessage(socket.get(), requestLimit);
    if (auto stop = request.find("stop"); stop && stop->asBoolean() == true) {
      listener = Descriptor{};
      writeMessage(socket.get(),
                   lsp::Json::object({{"status", lsp::Json::integer(0)}}));
      return;
    }
    auto arguments = request.find("arguments");
    auto values = arguments ? arguments->asArray() : nullptr;
    auto variables = request.find("environment");
    auto named = variables ? variables->asArray() : nullptr;
    auto mask = request.find("umask");
    auto permissions = mask ? mask->asInteger() : std::nullopt;
    if (!values || !named || !permissions || *permissions < 0 ||
        *permissions > 0777)
      throw std::runtime_error("missing resident compilation context");
    ::umask(static_cast<mode_t>(*permissions));
    lsp::Json::Array decodedArguments;
    for (const auto &value : *values)
      decodedArguments.push_back(lsp::Json::string(decodeBytes(&value)));
    std::vector<std::string> incomingEnvironment;
    for (const auto &value : *named) {
      auto text = decodeBytes(&value);
      if (text.find('\0') != std::string::npos ||
          text.find('=') == std::string::npos)
        throw std::runtime_error("invalid resident environment entry");
      incomingEnvironment.push_back(std::move(text));
    }
    if (!environmentInstalled || environment != incomingEnvironment) {
      ::environ = initialEnvironment;
      session = CompilationSession{};
      environment = std::move(incomingEnvironment);
      environmentPointers.clear();
      for (auto &entry : environment)
        environmentPointers.push_back(entry.data());
      environmentPointers.push_back(nullptr);
      ::environ = environmentPointers.data();
      environmentInstalled = true;
    }
    lsp::Json response;
    {
      RequestLifetime lifetime(socket.get());
      response = session.request(lsp::Json::object(
          {{"id", lsp::Json::integer(1)},
           {"arguments", lsp::Json::array(std::move(decodedArguments))}}));
    }
    for (auto name : {"stdout", "stderr"}) {
      auto text = response.find(name)->asString();
      response.add(std::string(name) + "Bytes",
                   lsp::Json::string(encodeBytes(*text)));
    }
    lsp::Json::Object encoded;
    for (const auto &[name, value] : *response.asObject())
      if (name != "stdout" && name != "stderr")
        encoded.emplace_back(name, value);
    writeMessage(socket.get(), lsp::Json::object(std::move(encoded)));
  }
}

Descriptor start(const Endpoint &endpoint) {
  if (auto socket = connect(endpoint); socket.get() >= 0)
    return socket;
  auto directory = privateDirectory(endpoint);
  auto lock = privateFile(directory.get(), endpoint.name + ".lock", O_RDWR);
  while (::flock(lock.get(), LOCK_EX))
    if (errno != EINTR)
      systemFailure("cannot lock resident compiler startup");
  if (auto socket = connect(endpoint); socket.get() >= 0)
    return socket;
  auto log =
      privateFile(directory.get(), endpoint.name + ".log", O_WRONLY | O_APPEND);
  std::array<int, 2> descriptors;
  if (::pipe2(descriptors.data(), O_CLOEXEC))
    systemFailure("cannot create resident compiler readiness pipe");
  Descriptor readReady(descriptors[0]), writeReady(descriptors[1]);
  auto child = ::fork();
  if (child < 0)
    systemFailure("cannot start resident compiler");
  if (!child) {
    readReady = Descriptor{};
    lock = Descriptor{};
    try {
      if (::setsid() < 0)
        systemFailure("cannot detach resident compiler");
      auto daemon = ::fork();
      if (daemon < 0)
        systemFailure("cannot start detached resident compiler");
      if (daemon)
        ::_exit(0);
      serve(endpoint, writeReady, log.get());
      ::_exit(0);
    } catch (const std::exception &error) {
      auto failure = errno ? errno : EIO;
      if (writeReady.get() >= 0)
        ::write(writeReady.get(), &failure, sizeof(failure));
      std::cerr << "mettle: error[resident]: " << error.what() << '\n';
      ::_exit(1);
    }
  }
  writeReady = Descriptor{};
  int status = 0;
  while (::waitpid(child, &status, 0) < 0)
    if (errno != EINTR)
      systemFailure("cannot join resident compiler startup");
  int failure = EIO;
  ssize_t size;
  do {
    size = ::read(readReady.get(), &failure, sizeof(failure));
  } while (size < 0 && errno == EINTR);
  if (size != sizeof(failure) || failure || !WIFEXITED(status) ||
      WEXITSTATUS(status)) {
    if (failure)
      errno = failure;
    systemFailure("resident compiler startup failed");
  }
  auto socket = connect(endpoint);
  if (socket.get() < 0)
    throw std::runtime_error("resident compiler exited during startup");
  return socket;
}
}
#endif

std::optional<int> residentCompilation(const Options &options, int argc,
                                       char **argv) {
#ifdef __linux__
  if (options.standalone || options.noCache ||
      (options.command != "check" && options.command != "build"))
    return {};
  try {
    rlimit cpu{};
    if (::getrlimit(RLIMIT_CPU, &cpu))
      systemFailure("cannot inspect resident compiler CPU budget");
    if (cpu.rlim_cur != RLIM_INFINITY)
      return {};
    auto socket = start(endpoint(options));
    lsp::Json::Array arguments, environment;
    for (int i = 1; i < argc; ++i)
      arguments.push_back(lsp::Json::string(encodeBytes(argv[i])));
    for (auto value = ::environ; *value; ++value)
      environment.push_back(lsp::Json::string(encodeBytes(*value)));
    auto permissions = ::umask(0);
    ::umask(permissions);
    writeMessage(socket.get(),
                 lsp::Json::object(
                     {{"arguments", lsp::Json::array(std::move(arguments))},
                      {"environment", lsp::Json::array(std::move(environment))},
                      {"umask", lsp::Json::integer(permissions)}}));
    auto response = readMessage(socket.get(), std::string{}.max_size());
    auto status = response.find("status");
    auto value = status ? status->asInteger() : std::nullopt;
    if (!value || *value < 0 || *value > std::numeric_limits<int>::max())
      throw std::runtime_error("resident compiler returned an invalid status");
    std::cout << decodeBytes(response.find("stdoutBytes"));
    std::cerr << decodeBytes(response.find("stderrBytes"));
    if (options.explain) {
      std::cerr << "mettle: resident compiler ";
      for (auto name :
           {"queryHits", "functionQueryHits", "instanceQueryHits"}) {
        auto count = response.find(name);
        if (!count || !count->asInteger() || *count->asInteger() < 0)
          throw std::runtime_error("resident compiler returned invalid reuse");
        std::cerr << name << "=" << *count->asInteger() << " ";
      }
      std::cerr << '\n';
    }
    return static_cast<int>(*value);
  } catch (const std::exception &error) {
    std::cerr << "mettle: error[resident]: " << error.what()
              << "; use --standalone to compile without the service\n";
    return 1;
  }
#else
  (void)options;
  (void)argc;
  (void)argv;
  return {};
#endif
}

int stopResidentCompilation(const Options &options) {
#ifdef __linux__
  try {
    auto socket = connect(endpoint(options));
    if (socket.get() < 0)
      return 0;
    writeMessage(socket.get(),
                 lsp::Json::object({{"stop", lsp::Json::boolean(true)}}));
    auto response = readMessage(socket.get(), std::string{}.max_size());
    auto status = response.find("status");
    if (!status || status->asInteger() != 0)
      throw std::runtime_error("resident compiler did not confirm shutdown");
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "mettle: error[resident]: " << error.what() << '\n';
    return 1;
  }
#else
  (void)options;
  return 0;
#endif
}
}
