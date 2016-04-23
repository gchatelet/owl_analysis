module common;

public import std.datetime;

struct PointKey {
  string device;
  SysTime ts; // timestamp

  @property bool valid() const { return device.length > 0 && ts != SysTime.init; }
}

struct Point {
  PointKey key;
  alias key this;
  double value;
}
