const std = @import("std");

/// Server metrics for observability
pub const Metrics = struct {
    request_count: u64 = 0,
    error_count: u64 = 0,
    total_latency_ns: u64 = 0,
    min_latency_ns: u64 = std.math.maxInt(u64),
    max_latency_ns: u64 = 0,
    start_time: i64,

    pub fn init() Metrics {
        return Metrics{
            .start_time = std.time.timestamp(),
        };
    }

    pub fn recordRequest(self: *Metrics, latency_ns: u64, is_error: bool) void {
        self.request_count += 1;
        self.total_latency_ns += latency_ns;

        if (latency_ns < self.min_latency_ns) {
            self.min_latency_ns = latency_ns;
        }
        if (latency_ns > self.max_latency_ns) {
            self.max_latency_ns = latency_ns;
        }

        if (is_error) {
            self.error_count += 1;
        }
    }

    pub fn avgLatencyMs(self: *const Metrics) f64 {
        if (self.request_count == 0) return 0;
        const avg_ns = self.total_latency_ns / self.request_count;
        return @as(f64, @floatFromInt(avg_ns)) / 1_000_000.0;
    }

    pub fn minLatencyMs(self: *const Metrics) f64 {
        if (self.min_latency_ns == std.math.maxInt(u64)) return 0;
        return @as(f64, @floatFromInt(self.min_latency_ns)) / 1_000_000.0;
    }

    pub fn maxLatencyMs(self: *const Metrics) f64 {
        return @as(f64, @floatFromInt(self.max_latency_ns)) / 1_000_000.0;
    }

    pub fn uptimeSeconds(self: *const Metrics) i64 {
        return std.time.timestamp() - self.start_time;
    }

    /// Format metrics as Prometheus text format
    pub fn formatPrometheus(self: *const Metrics, buf: []u8) ![]const u8 {
        var stream = std.io.fixedBufferStream(buf);
        const writer = stream.writer();

        try writer.print(
            \\# HELP nano_requests_total Total number of HTTP requests
            \\# TYPE nano_requests_total counter
            \\nano_requests_total {d}
            \\# HELP nano_errors_total Total number of error responses
            \\# TYPE nano_errors_total counter
            \\nano_errors_total {d}
            \\# HELP nano_request_latency_ms_avg Average request latency in milliseconds
            \\# TYPE nano_request_latency_ms_avg gauge
            \\nano_request_latency_ms_avg {d:.2}
            \\# HELP nano_request_latency_ms_min Minimum request latency in milliseconds
            \\# TYPE nano_request_latency_ms_min gauge
            \\nano_request_latency_ms_min {d:.2}
            \\# HELP nano_request_latency_ms_max Maximum request latency in milliseconds
            \\# TYPE nano_request_latency_ms_max gauge
            \\nano_request_latency_ms_max {d:.2}
            \\# HELP nano_uptime_seconds Server uptime in seconds
            \\# TYPE nano_uptime_seconds counter
            \\nano_uptime_seconds {d}
            \\
        , .{
            self.request_count,
            self.error_count,
            self.avgLatencyMs(),
            self.minLatencyMs(),
            self.maxLatencyMs(),
            self.uptimeSeconds(),
        });

        return stream.getWritten();
    }

    /// Format metrics as JSON
    pub fn formatJson(self: *const Metrics, buf: []u8) ![]const u8 {
        var stream = std.io.fixedBufferStream(buf);
        const writer = stream.writer();

        try writer.print(
            \\{{"requests":{d},"errors":{d},"latency_ms":{{"avg":{d:.2},"min":{d:.2},"max":{d:.2}}},"uptime_s":{d}}}
        , .{
            self.request_count,
            self.error_count,
            self.avgLatencyMs(),
            self.minLatencyMs(),
            self.maxLatencyMs(),
            self.uptimeSeconds(),
        });

        return stream.getWritten();
    }
};
