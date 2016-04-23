module owl_log;

import common;

Point parseLogLineAsDevicePoint(char[] line) {
  import std.algorithm : countUntil;
  const split = line.countUntil(' ');
  // The parsing function is slow and allocates memory :(
  const ElectricityMessage message = parseXmlLine(line[split..$]);
	Point output;
  if(message.valid) {
		const ts = SysTime.fromISOExtString(line[0..split]);
		output.key = PointKey(message.device_id, ts);
		output.value = message.channels[0].day_Wh / 1000;
  }
	return output;
}

struct Channel {
  double current_w;
  double day_Wh;
}

struct ElectricityMessage {
  string device_id;
  Channel[3] channels;

  @property bool valid() const { return device_id.length > 0; }
}

ElectricityMessage parseXmlLine(char[] xmlString) {
  // The xml sent by owl intuition is not standard and uses ' instead of ".
  import std.algorithm : each;
  xmlString.each!((ref a) {if(a=='\'') a='"';})();
  import std.xml;
  scope xml = new DocumentParser(cast(string)xmlString);
  auto output = ElectricityMessage();
  if(xml.tag !is null && xml.tag.name == "electricity") {
    output.device_id = xml.tag.attr["id"].idup;
    xml.onStartTag["chan"] = (ElementParser a) {
      import std.conv : to;
      const size_t channel_id = a.tag.attr["id"].to!size_t;
      auto channel = &output.channels[channel_id];
      a.onEndTag["day"] = (in Element b) {
        channel.day_Wh = b.text.to!float;
      };
      a.onEndTag["curr"] = (in Element b) {
        channel.current_w = b.text.to!float;
      };
      a.parse();
    };
    xml.parse();
  }
  return output;
}

unittest {
  char[] input = `gibberish`.dup;
  const result = parseXmlLine(input);
  assert(!result.valid());
}

unittest {
  char[] input = `<weather id='443719000B8E' code='116'>
  <temperature>10.00</temperature>
  <text>Partly Cloudy</text>
  </weather>`.dup;
  auto result = parseXmlLine(input);
  assert(!result.valid());
}

unittest {
  char[] input = `<electricity id='443719000B8E'>
  <signal rssi='-79' lqi='127'/>
  <battery level='100%'/>
  <chan id='0'><curr units='w'>2608.00</curr><day units='wh'>26583.98</day></chan>
  <chan id='1'><curr units='w'>0.00</curr><day units='wh'>0.00</day></chan>
  <chan id='2'><curr units='w'>0.00</curr><day units='wh'>0.00</day></chan>
  </electricity>`.dup;
  auto result = parseXmlLine(input);
  assert(result.valid());
  assert(result.device_id == "443719000B8E");
  assert(result.channels[0].current_w == 2608.00f);
  assert(result.channels[0].day_Wh == 26583.98f);
  assert(result.channels[1].current_w == 0f);
  assert(result.channels[1].day_Wh == 0f);
  assert(result.channels[2].current_w == 0f);
  assert(result.channels[2].day_Wh == 0f);
}
