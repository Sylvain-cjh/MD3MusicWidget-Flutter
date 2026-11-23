#pragma once
#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>



class NativeArtworkReader {
public:
  using Cancelled = std::function<bool()>;
  using Work = std::function<std::vector<uint8_t>(const Cancelled &)>;
  struct Result {
    std::string key;
    std::vector<uint8_t> bytes;
    bool succeeded = false;
  };
  NativeArtworkReader() : state_(std::make_shared<State>()) {}
  ~NativeArtworkReader() {
    const auto state = state_;
    std::lock_guard lock(state->mutex);
    state->stop = true;
    ++state->serial;
    state->queued.reset();
    state->wake.notify_one();
  }
  NativeArtworkReader(const NativeArtworkReader &) = delete;
  NativeArtworkReader &operator=(const NativeArtworkReader &) = delete;

  void Reset() {
    std::lock_guard lock(state_->mutex);
    ++state_->serial;
    state_->key.clear();
    state_->pending = false;
    state_->queued.reset();
    state_->completed.reset();
  }

  void Submit(std::string key, Work work, std::function<void()> ready) {
    std::lock_guard lock(state_->mutex);
    if (state_->stop || (state_->pending && state_->key == key) ||
        (state_->completed && state_->completed->key == key)) return;
    if (!state_->started) {
      std::thread(Run, state_).detach();
      state_->started = true;
    }
    const auto serial = ++state_->serial;
    state_->key = key;
    state_->pending = true;
    state_->completed.reset();
    state_->queued = Job{std::move(key), std::move(work), std::move(ready), serial};
    state_->wake.notify_one();
  }

  std::optional<Result> Take(const std::string &key) {
    std::lock_guard lock(state_->mutex);
    if (!state_->completed || state_->completed->key != key) return {};
    auto result = std::move(state_->completed);
    state_->completed.reset();
    return result;
  }

  bool Pending(const std::string &key) const {
    std::lock_guard lock(state_->mutex);
    
    return (state_->pending && state_->key == key) ||
           (state_->completed && state_->completed->key == key);
  }

private:
  struct Job {
    std::string key;
    Work work;
    std::function<void()> ready;
    uint64_t serial;
  };
  struct State {
    std::mutex mutex;
    std::condition_variable wake;
    std::atomic<bool> stop{false};
    std::atomic<uint64_t> serial{0};
    bool started = false, pending = false;
    std::string key;
    std::optional<Job> queued;
    std::optional<Result> completed;
  };
  static void Run(std::shared_ptr<State> state) {
    while (!state->stop) {
      std::optional<Job> job;
      {
        std::unique_lock lock(state->mutex);
        state->wake.wait(lock, [&] { return state->stop || state->queued; });
        if (state->stop) return;
        job = std::move(state->queued);
        state->queued.reset();
      }
      const Cancelled cancelled = [state, serial = job->serial] {
        return state->stop || state->serial != serial;
      };
      Result result{job->key, {}, false};
      try {
        result.bytes = job->work(cancelled);
        result.succeeded = !result.bytes.empty();
      } catch (...) {}
      {
        std::lock_guard lock(state->mutex);
        if (cancelled()) continue;
        state->completed = std::move(result);
        state->pending = false;
      }
      try { job->ready(); } catch (...) {}
    }
  }
  std::shared_ptr<State> state_;
};
