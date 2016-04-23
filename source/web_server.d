module web_server;

import std.datetime;
import std.range;
import std.algorithm;
import std.format;

import vibe.data.json;
import vibe.web.web;

import redis_db;

class WebInterface {
	@path(":device/:year/:month/:day/consumption")
	Json getDayConsumption(string _device, ushort _year, ubyte _month, ubyte _day) {
		return Json(redis_db.getDayConsumption(_device, Date(_year, _month, _day)));
	}

	@path(":device/:year/:month/:day")
	void getDay(string _device, ushort _year, ubyte _month, ubyte _day) {
		auto text =
			getHourBucketsForDay(_device, Date(_year, _month, _day))[]
			.enumerate(0)
			.map!(a => format("[[%d, 30, 0], %s]", a[0], a[1]))
      .joiner(", ")
      .array;
    render!("day_chart.dt", text);
  }

	@path(":device/:year/:month")
	void getMonth(string _device, ushort _year, ubyte _month) {
		const text =
			datesInMonth(_year, _month)
			.map!(date => tuple(date, redis_db.getDayConsumption(_device, date)))
			.map!(a => format("[new Date(%d, %d, %d), %s]", a[0].year, a[0].month - 1, a[0].day, a[1]))
			.joiner(", ")
			.array;
		render!("month_chart.dt", text);
	}

	@path(":device/:year")
	void getYear(string _device, ushort _year) {
		const text =
			datesInYear(_year)
			.map!(date => tuple(date, redis_db.getDayConsumption(_device, date)))
			.map!(a => format("[new Date(%d, %d, %d), %s]", a[0].year, a[0].month - 1, a[0].day, a[1]))
			.joiner(", ")
			.array;
		render!("month_chart.dt", text);
	}

	@path(":device/:year/report")
	Json getYearReport(string _device, ushort _year) {
		return datesInYear(_year)
			.map!(date => getDayReport(_device, date))
			.array
			.serializeToJson;
	}
}

double[] adjacentDiff(double[] values) {
	foreach_reverse(i ; 1 .. values.length) values[i] -= values[i - 1];
	return values;
}

auto datesInMonth(ushort year, ubyte month) {
	return iota(1, Date(year, month, 1).daysInMonth())
		.map!(day => Date(year, month, day));
}

auto datesInYear(ushort year) {
	return iota(Month.jan, Month.dec + 1)
		.map!(month => datesInMonth(year, cast(ubyte)month))
		.join;
}
