const std = @import("std");
const network = @import("network");

const MqttClient = @This();

const c = @cImport({
    @cInclude("mqtt.h");
});

socket: ?network.Socket,
client: c.mqtt_client,

sendbuf: [2048]u8, // sendbuf should be large enough to hold multiple whole mqtt messages
recvbuf: [1024]u8, // recvbuf should be large enough any whole mqtt message expected to be received

publish_response_callback_ptr: ?*anyopaque,
publish_response_callback: ?*const fn (?*anyopaque, *MqttClient, PublishResponse) void,

pub fn init(self: *MqttClient) !void {
    self.* = .{
        .socket = null,
        .client = undefined,
        .sendbuf = undefined,
        .recvbuf = undefined,
        .publish_response_callback_ptr = null,
        .publish_response_callback = null,
    };
}

pub fn setPublishResponseCallback(mqtt: *MqttClient, context: anytype, comptime callback: fn (@TypeOf(context), *MqttClient, PublishResponse) void) void {
    const C = @TypeOf(context);
    const H = struct {
        fn cb(ctx: ?*anyopaque, mq: *MqttClient, resp: PublishResponse) void {
            callback(@ptrCast(C, @alignCast(@alignOf(C), ctx)), mq, resp);
        }
    };

    mqtt.publish_response_callback = H.cb;
    mqtt.publish_response_callback_ptr = context;
    mqtt.client.publish_response_callback_state = mqtt;
}

fn publishCallback(state_ptr: ?*?*anyopaque, publish_ptr: ?*c.mqtt_response_publish) callconv(.C) void {
    const mqtt = @ptrCast(*MqttClient, @alignCast(@alignOf(MqttClient), state_ptr.?.*.?));

    const published = publish_ptr orelse return;
    const topic = @ptrCast([*]const u8, published.topic_name.?)[0..published.topic_name_size];
    const message = @ptrCast([*]const u8, published.application_message.?)[0..published.application_message_size];

    const response = PublishResponse{
        .topic = topic,
        .payload = message,
        .dup_flag = (published.dup_flag != 0),
        .qos_level = @intToEnum(QoS, published.qos_level),
        .packet_id = published.packet_id,
        .retain_flag = (published.retain_flag != 0),
    };

    if (mqtt.publish_response_callback) |callback| {
        callback(mqtt.publish_response_callback_ptr, mqtt, response);
    }
}

pub const PublishResponse = struct {
    topic: []const u8,
    payload: []const u8,
    dup_flag: bool,
    qos_level: QoS,
    retain_flag: bool,
    packet_id: u16,
};

pub const LastWill = struct {
    topic: [:0]const u8,
    message: []const u8,
};
pub fn connect(
    self: *MqttClient,
    host_name: []const u8,
    port: ?u16,
    client_id: ?[:0]const u8,
    last_will: ?LastWill,
) !void {
    std.debug.assert(self.socket == null);

    self.socket = try network.connectToHost(
        std.heap.page_allocator,
        host_name,
        port orelse 1883,
        .tcp,
    );

    // set socket to nonblocking
    const flags = try std.os.fcntl(self.socket.?.internal, std.os.F.GETFL, 0);
    _ = try std.os.fcntl(self.socket.?.internal, std.os.F.SETFL, flags | std.os.O.NONBLOCK);

    try wrapMqttErr(c.mqtt_init(
        &self.client,
        self.socket.?.internal,
        &self.sendbuf,
        self.sendbuf.len,
        &self.recvbuf,
        self.recvbuf.len,
        publishCallback,
    ));

    // Ensure we have a clean session
    const connect_flags: u8 = c.MQTT_CONNECT_CLEAN_SESSION;
    // Send connection request to the broker.
    try wrapMqttErr(c.mqtt_connect(
        &self.client,
        if (client_id) |ptr| ptr.ptr else null,
        if (last_will) |will| will.topic.ptr else null, // last will topic
        if (last_will) |will| will.message.ptr else null, // last will message
        if (last_will) |will| will.message.len else 0, // last will message len
        null, // user name
        null, // password
        connect_flags,
        400, // keep alive
    ));
}

pub fn deinit(self: *MqttClient) void {
    if (self.socket) |*sock| {
        sock.close();
    }
    self.* = undefined;
}

pub fn subscribe(self: *MqttClient, topic: [:0]const u8) !void {
    try wrapMqttErr(c.mqtt_subscribe(
        &self.client,
        topic.ptr,
        0, // TODO: Figure out what this exactly does
    ));
}

pub fn sync(self: *MqttClient) !void {
    try wrapMqttErr(c.mqtt_sync(&self.client));
}

pub fn publish(
    self: *MqttClient,
    topic: [:0]const u8,
    message: []const u8,
    qos: QoS,
    retain: bool,
) !void {
    const flags: u8 = @intCast(u8, @enumToInt(qos) | if (retain) c.MQTT_PUBLISH_RETAIN else 0);
    try wrapMqttErr(c.mqtt_publish(
        &self.client,
        topic.ptr,
        message.ptr,
        message.len,
        flags,
    ));
}

fn wrapMqttErr(err: c.MQTTErrors) !void {
    if (err == c.MQTT_OK)
        return;

    std.log.err("mqtt error: {s}\n", .{std.mem.sliceTo(c.mqtt_error_str(err).?, 0)});

    return switch (err) {
        c.MQTT_ERROR_NULLPTR => error.Nullptr,
        c.MQTT_ERROR_CONTROL_FORBIDDEN_TYPE => error.ControlForbiddenType,
        c.MQTT_ERROR_CONTROL_INVALID_FLAGS => error.ControlInvalidFlags,
        c.MQTT_ERROR_CONTROL_WRONG_TYPE => error.ControlWrongType,
        c.MQTT_ERROR_CONNECT_CLIENT_ID_REFUSED => error.ConnectClientIdRefused,
        c.MQTT_ERROR_CONNECT_NULL_WILL_MESSAGE => error.ConnectNullWillMessage,
        c.MQTT_ERROR_CONNECT_FORBIDDEN_WILL_QOS => error.ConnectForbiddenWillQos,
        c.MQTT_ERROR_CONNACK_FORBIDDEN_FLAGS => error.ConnackForbiddenFlags,
        c.MQTT_ERROR_CONNACK_FORBIDDEN_CODE => error.ConnackForbiddenCode,
        c.MQTT_ERROR_PUBLISH_FORBIDDEN_QOS => error.PublishForbiddenQos,
        c.MQTT_ERROR_SUBSCRIBE_TOO_MANY_TOPICS => error.SubscribeTooManyTopics,
        c.MQTT_ERROR_MALFORMED_RESPONSE => error.MalformedResponse,
        c.MQTT_ERROR_UNSUBSCRIBE_TOO_MANY_TOPICS => error.UnsubscribeTooManyTopics,
        c.MQTT_ERROR_RESPONSE_INVALID_CONTROL_TYPE => error.ResponseInvalidControlType,
        c.MQTT_ERROR_CONNECT_NOT_CALLED => error.ConnectNotCalled,
        c.MQTT_ERROR_SEND_BUFFER_IS_FULL => error.SendBufferIsFull,
        c.MQTT_ERROR_SOCKET_ERROR => error.SocketError,
        c.MQTT_ERROR_MALFORMED_REQUEST => error.MalformedRequest,
        c.MQTT_ERROR_RECV_BUFFER_TOO_SMALL => error.RecvBufferTooSmall,
        c.MQTT_ERROR_ACK_OF_UNKNOWN => error.AckOfUnknown,
        c.MQTT_ERROR_NOT_IMPLEMENTED => error.NotImplemented,
        c.MQTT_ERROR_CONNECTION_REFUSED => error.ConnectionRefused,
        c.MQTT_ERROR_SUBSCRIBE_FAILED => error.SubscribeFailed,
        c.MQTT_ERROR_CONNECTION_CLOSED => error.ConnectionClosed,
        c.MQTT_ERROR_INITIAL_RECONNECT => error.InitialReconnect,
        c.MQTT_ERROR_INVALID_REMAINING_LENGTH => error.InvalidRemainingLength,
        c.MQTT_ERROR_CLEAN_SESSION_IS_REQUIRED => error.CleanSessionIsRequired,
        c.MQTT_ERROR_RECONNECTING => error.Reconnecting,
        else => error.Unexpected,
    };
}

pub const QoS = enum(c_int) {
    at_most_once = c.MQTT_PUBLISH_QOS_0,
    at_least_once = c.MQTT_PUBLISH_QOS_1,
    exactly_once = c.MQTT_PUBLISH_QOS_2,
};
