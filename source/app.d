import std.stdio;
import std.traits : EnumMembers;
import std.conv : to;

import vibe.core.args;
import vibe.core.core;

import redis_db;

enum Mode {clean_db_and_ingest, web_server, owl_packet_listener}
enum ModeStrings = () pure {
  string[] output;
  foreach(mode; EnumMembers!Mode) output ~= mode.to!string;
  return output;
}();

void cleanDbAndIngest() {
  const ingest_file = readRequiredOption!string("file", "The file to read data from.");
  writeln("Cleaning redis db");
  cleanDb();
  writeln("Ingesting data from ", ingest_file);
  import owl_log;
  import std.algorithm : filter, each;
  File(ingest_file)
    .byLine
    .map!parseLogLineAsDevicePoint
    .filter!(a => a.valid)
    .each!(a => a.putInDb());
  writeln("Done");
}

void webServer() {
  import web_server;
  import vibe.web.web;
  import vibe.http.router;
  import vibe.http.server;
  const port = readRequiredOption!ushort("port", "The web server port.");
  auto router = new URLRouter;
  router.registerWebInterface(new WebInterface);
  auto settings = new HTTPServerSettings;
  settings.port = port;
  settings.useCompressionIfPossible = true;
  listenHTTP(settings, router);
  startEventLoop();
}

void listenToOwlPackets() {
  const port = readRequiredOption!ushort("port", "The UDP port to listen to.");
  runTask({
    auto udp_listener = listenUDP(port);
    while (true) {
      auto pack = cast(string)udp_listener.recv();
      import std.datetime;
      import vibe.core.file;
      try {
        appendToFile(getWorkingDirectory() ~ "owl_events.log", format("%s %s\n", Clock.currTime.toISOExtString(), pack));
      } catch {}
    }
  });
  startEventLoop();
}

void startEventLoop() {
  lowerPrivileges();
	runEventLoop();
}

void main() {
  import std.format : format;
  string mode;
  readOption("mode", &mode, format("One of %-(%s, %).", ModeStrings));
  try {
    import std.exception : enforce;
    switch(mode) {
      default:
        enforce(false, format("--mode must be one of %-(%s, %).", ModeStrings));
        break;
      case Mode.clean_db_and_ingest.to!string:
        cleanDbAndIngest();
        break;
      case Mode.web_server.to!string:
        webServer();
        break;
      case Mode.owl_packet_listener.to!string:
        listenToOwlPackets();
        break;
    }
  } catch(Exception e) {
    writeln(e.msg);
    printCommandLineHelp();
  }
}
