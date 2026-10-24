#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <complex>
#include <cstdint>
#include <cstring>
#include <vector>



class NativeSpectrumDsp {
public:
  static constexpr int kSize = 2048, kBands = 32;
  explicit NativeSpectrumDsp(int rate = 48000) {
    constexpr double pi = 3.14159265358979323846;
    for (int i = 0; i < kSize; ++i)
      window_[i] =
          static_cast<float>(0.54 - 0.46 * std::cos(2 * pi * i / (kSize - 1)));
    const double ratio = std::min(16000.0, rate * 0.45) / 45.0;
    for (int b = 0; b < kBands; ++b) {
      starts_[b] =
          std::clamp(static_cast<int>(std::floor(
                         45 * std::pow(ratio, b / 32.0) * kSize / rate)),
                     1, kSize / 2 - 1);
      ends_[b] =
          std::clamp(static_cast<int>(std::ceil(
                         45 * std::pow(ratio, (b + 1) / 32.0) * kSize / rate)),
                     starts_[b] + 1, kSize / 2);
    }
  }
  bool Push(const float *samples, size_t count, int64_t now) {
    for (size_t i = 0; i < count; ++i) {
      const float sample =
          std::isfinite(samples[i]) ? std::clamp(samples[i], -1.0f, 1.0f) : 0;
      ring_[write_] = sample;
      write_ = (write_ + 1) % kSize;
      total_++;
      hop_++;
    }
    if (total_ < kSize || hop_ < 1024 || now - updated_ < 33)
      return false;
    hop_ = 0;
    double sum = 0;
    for (int i = 0; i < kSize; ++i) {
      auto s = ring_[(write_ + i) % kSize];
      sum += s * s;
      fft_[i] = {s * window_[i], 0};
    }
    rms_ = std::sqrt(sum / kSize);
    if (rms_ < 0.0007) {
      
      
      for (auto &level : levels_)
        level += (0 - level) * 0.18f;
      updated_ = now;
      return true;
    }
    for (int i = 1, j = 0; i < kSize; ++i) {
      int bit = kSize >> 1;
      for (; j & bit; bit >>= 1)
        j ^= bit;
      j ^= bit;
      if (i < j)
        std::swap(fft_[i], fft_[j]);
    }
    constexpr float pi = 3.14159265358979323846f;
    for (int len = 2; len <= kSize; len <<= 1) {
      const auto root = std::polar(1.0f, -2 * pi / len);
      for (int i = 0; i < kSize; i += len) {
        std::complex<float> w(1, 0);
        for (int j = 0; j < len / 2; ++j) {
          auto a = fft_[i + j], b = fft_[i + j + len / 2] * w;
          fft_[i + j] = a + b;
          fft_[i + j + len / 2] = a - b;
          w *= root;
        }
      }
    }
    for (int b = 0; b < kBands; ++b) {
      double energy = 0;
      for (int i = starts_[b]; i < ends_[b]; ++i)
        energy += std::abs(fft_[i]) / kSize;
      const double db =
          20 * std::log10(energy / (ends_[b] - starts_[b]) + 1e-9);
      const float target =
          rms_ < 0.0007 ? 0
                        : static_cast<float>(
                              std::sqrt(std::clamp((db + 92) / 72, 0.0, 1.0)));
      levels_[b] +=
          (target - levels_[b]) * (target > levels_[b] ? 0.62f : 0.18f);
    }
    updated_ = now;
    return true;
  }
  std::vector<uint8_t> Packet(bool available, int64_t now) const {
    std::vector<uint8_t> bytes(12 + kBands * 4, 0);
    bytes[0] = 1;
    bytes[1] = available ? 1 : 0;
    bytes[2] = kBands;
    std::memcpy(bytes.data() + 4, &updated_, 8);
    const auto age = now - updated_;
    const float decay =
        updated_ <= 0 || age > 900 ? 0
        : age <= 100               ? 1
                     : static_cast<float>(std::pow(0.78, (age - 100) / 50.0));
    for (int b = 0; b < kBands; ++b) {
      float value = std::clamp(levels_[b] * decay, 0.0f, 1.0f);
      std::memcpy(bytes.data() + 12 + b * 4, &value, 4);
    }
    return bytes;
  }
  const std::array<float, kBands> &Levels() const { return levels_; }
  double Rms() const { return rms_; }

private:
  std::array<float, kSize> ring_{}, window_{};
  std::array<std::complex<float>, kSize> fft_{};
  std::array<int, kBands> starts_{}, ends_{};
  std::array<float, kBands> levels_{};
  int write_ = 0;
  uint64_t total_ = 0, hop_ = 0;
  int64_t updated_ = 0;
  double rms_ = 0;
};
