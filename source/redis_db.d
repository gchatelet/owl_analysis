module redis_db;

public import vibe.db.redis.redis;

import std.range;
import std.algorithm;
import std.conv : to;

import common;

RedisDatabase g_redis_db;

string keyForDay(string namespace)(in string device, in SysTime systime) {
  return device ~ ":" ~ namespace ~ ":date:" ~ (cast(Date)systime).toISOExtString;
}

unittest {
	assert(keyForDay!"store"("dev1", SysTime.fromUnixTime(1460757632).hour)
		== "dev1:store:date:2016-04-16");
	assert(keyForDay!"data"("dev2", Date.fromUnixTime(1460757599))
		== "dev2:data:date:2016-04-15");
}

void putInDb(in Point point) {
  g_redis_db.sadd("devices", point.device);

  struct SortedSetValue {
    string key;
    long score;
    double value;
  }
  auto bucket(alias keyFun)(in Point point) {
    return SortedSetValue(
      keyFun(point.device, point.ts),
      point.ts.toUnixTime!long,
      point.value
    );
  }
  void push(ref RedisDatabase db, SortedSetValue[] insertions...) {
    foreach(const ref insertion ; insertions) {
      db.zadd(insertion.key, insertion.score, insertion.value);
    }
  }
  push(g_redis_db, bucket!(keyForDay!"store")(point));
}

shared static this() {
  RedisClient redis_client = connectRedis("localhost");
  g_redis_db = redis_client.getDatabase(0);
}

void cleanDb() {
  g_redis_db.deleteAll();
}

SysTime parseTimestamp(string ts) {
  return SysTime(unixTimeToStdTime(ts.to!long));
}

double[24] getHourBucketsForDay(string device, Date date) {
	double[24] maxValueForHour;
	const storeKey = keyForDay!"store"(device, SysTime(date));
	g_redis_db.zrange!string(storeKey, 0, -1, true)
		.array
		.chunks(2)
		.each!(a => maxValueForHour[parseTimestamp(a[1]).hour] = a[0].to!double);
    import std.math : isNaN;
		foreach(ref value; maxValueForHour) {
			if(isNaN(value)) value = 0;
		}
	return maxValueForHour;
}

double getDayConsumption(string device, Date date) {
	const storeKey = keyForDay!"store"(device, SysTime(date));
	auto values = g_redis_db.zrange!double(storeKey, -1, -1);
	return values.empty ? 0 : values.front;
}

struct DayReport {
	Date date;
	float completeness;
}

DayReport getDayReport(string device, Date date) {
	const storeKey = keyForDay!"store"(device, SysTime(date));
	auto values = g_redis_db.zrange!string(storeKey, 0, -1, true)
		.array
		.chunks(2);
	DayReport report = DayReport(date);
	TimeOfDay min = TimeOfDay.max;
	TimeOfDay max = TimeOfDay.min;
	double previous;
	bool corrupted;
	foreach(pair; values) {
		const value = pair[0].to!double;
		const timeOfDay = cast(TimeOfDay)parseTimestamp(pair[1]);
		if(timeOfDay < min) min = timeOfDay;
		if(timeOfDay > max) max = timeOfDay;
		if(previous != previous.init && value <= previous) {
			corrupted = true;
			break;
		}
		previous = value;
	}
	report.completeness =
		corrupted ? -1 :
			min > max ? 0 :
				100f * (max - min).total!"seconds" / 24.hours.total!"seconds";
	return report;
}
