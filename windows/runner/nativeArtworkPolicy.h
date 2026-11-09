#pragma once

#include <cstdint>

struct NativeArtworkDecision {
  bool advance_track;
  bool invalidate_cover;
  bool read_thumbnail;
};



constexpr NativeArtworkDecision DecideNativeArtwork(
    bool identity_changed, bool metadata_changed, double previous_position_ms,
    double position_ms, std::int64_t retry_at_ms, std::int64_t now_ms) {
  const bool timeline_restart =
      previous_position_ms > 5000 && position_ms + 1500 < previous_position_ms;
  const bool retry_due = retry_at_ms > 0 && now_ms >= retry_at_ms;
  return {identity_changed || timeline_restart, identity_changed,
          identity_changed || metadata_changed || retry_due};
}
