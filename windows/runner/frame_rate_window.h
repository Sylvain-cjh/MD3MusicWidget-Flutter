#ifndef RUNNER_FRAME_RATE_WINDOW_H_
#define RUNNER_FRAME_RATE_WINDOW_H_

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <deque>
#include <map>
#include <optional>
#include <sstream>
#include <string>
#include <vector>



class FrameRateWindow {
 public:
  void Reset() { columns_.clear(); chains_.clear(); }

  void AddCsv(const std::string& line, double received_seconds) {
    const auto fields = SplitCsv(line);
    if (fields.empty()) return;
    if (fields[0] == "Application") {
      columns_.clear();
      for (size_t i = 0; i < fields.size(); ++i) columns_[fields[i]] = i;
      return;
    }
    const auto chain_column = columns_.find("SwapChainAddress");
    const auto time_column = columns_.find("TimeInSeconds");
    if (chain_column == columns_.end() || time_column == columns_.end() ||
        chain_column->second >= fields.size() || time_column->second >= fields.size()) return;
    char* end = nullptr;
    const auto& value = fields[time_column->second];
    const double timestamp = std::strtod(value.c_str(), &end);
    if (end == value.c_str() || *end != '\0' || !std::isfinite(timestamp)) return;
    auto& chain = chains_[fields[chain_column->second]];
    if (!chain.frames.empty() && timestamp <= chain.frames.back()) return;
    chain.received = received_seconds;
    chain.frames.push_back(timestamp);
    while (chain.frames.size() > 2 &&
           (timestamp - chain.frames.front() > 1.0 || chain.frames.size() > 4096)) {
      chain.frames.pop_front();
    }
    if (chains_.size() > 32) {
      auto oldest = std::min_element(chains_.begin(), chains_.end(),
        [](const auto& a, const auto& b) { return a.second.received < b.second.received; });
      chains_.erase(oldest);
    }
  }

  std::optional<double> Fps(double now_seconds) const {
    const Chain* busiest = nullptr;
    for (const auto& item : chains_) {
      const auto& chain = item.second;
      if (now_seconds - chain.received > 1.5 || chain.frames.size() < 3) continue;
      if (!busiest || chain.frames.size() > busiest->frames.size()) busiest = &chain;
    }
    if (!busiest) return std::nullopt;
    const double span = busiest->frames.back() - busiest->frames.front();
    if (span <= 0) return std::nullopt;
    return static_cast<double>(busiest->frames.size() - 1) / span;
  }

 private:
  struct Chain { std::deque<double> frames; double received = 0; };
  std::map<std::string, size_t> columns_;
  std::map<std::string, Chain> chains_;

  static std::vector<std::string> SplitCsv(const std::string& line) {
    std::vector<std::string> fields;
    std::string field;
    bool quoted = false;
    for (size_t i = 0; i < line.size(); ++i) {
      const char c = line[i];
      if (c == '"') {
        if (quoted && i + 1 < line.size() && line[i + 1] == '"') { field += c; ++i; }
        else quoted = !quoted;
      } else if (c == ',' && !quoted) { fields.push_back(field); field.clear(); }
      else if (c != '\r') field += c;
    }
    fields.push_back(field);
    return fields;
  }
};
#endif
