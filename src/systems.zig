const std = @import("std");
const mem = std.mem;
const StructField = std.builtin.Type.StructField;

const Entities = @import("entities.zig").Entities;
const Modules = @import("modules.zig").Modules;
const EntityID = @import("entities.zig").EntityID;
const comp = @import("comptime.zig");

pub fn World(comptime mods: anytype) type {
    const modules = Modules(mods);

    return struct {
        allocator: mem.Allocator,
        entities: Entities(modules.components),
        mod: Mods(),

        const Self = @This();

        pub fn Mod(comptime module_tag: anytype) type {
            const State = @TypeOf(@field(@as(modules.State, undefined), @tagName(module_tag)));
            const components = @field(modules.components, @tagName(module_tag));
            return struct {
                state: State,
                entities: *Entities(modules.components),
                allocator: mem.Allocator,

                /// Sets the named component to the specified value for the given entity,
                /// moving the entity from it's current archetype table to the new archetype
                /// table if required.
                pub inline fn set(
                    m: *@This(),
                    entity: EntityID,
                    comptime component_name: std.meta.DeclEnum(components),
                    component: @field(components, @tagName(component_name)),
                ) !void {
                    const mod_ptr: *Self.Mods() = @alignCast(@fieldParentPtr(Mods(), @tagName(module_tag), m));
                    const world = @fieldParentPtr(Self, "mod", mod_ptr);
                    try world.entities.setComponent(entity, module_tag, component_name, component);
                }

                /// gets the named component of the given type (which must be correct, otherwise undefined
                /// behavior will occur). Returns null if the component does not exist on the entity.
                pub inline fn get(
                    m: *@This(),
                    entity: EntityID,
                    comptime component_name: std.meta.DeclEnum(components),
                ) ?@field(components, @tagName(component_name)) {
                    const mod_ptr: *Self.Mods() = @alignCast(@fieldParentPtr(Mods(), @tagName(module_tag), m));
                    const world = @fieldParentPtr(Self, "mod", mod_ptr);
                    return world.entities.getComponent(entity, module_tag, component_name);
                }

                /// Removes the named component from the entity, or noop if it doesn't have such a component.
                pub inline fn remove(
                    m: *@This(),
                    entity: EntityID,
                    comptime component_name: std.meta.DeclEnum(components),
                ) !void {
                    const mod_ptr: *Self.Mods() = @alignCast(@fieldParentPtr(Mods(), @tagName(module_tag), m));
                    const world = @fieldParentPtr(Self, "mod", mod_ptr);
                    try world.entities.removeComponent(entity, module_tag, component_name);
                }

                fn upper(c: u8) u8 {
                    return switch (c) {
                        'a' => 'A',
                        'b' => 'B',
                        'c' => 'C',
                        'd' => 'D',
                        'e' => 'E',
                        'f' => 'F',
                        'g' => 'G',
                        'h' => 'H',
                        'i' => 'I',
                        'j' => 'J',
                        'k' => 'K',
                        'l' => 'L',
                        'm' => 'M',
                        'n' => 'N',
                        'o' => 'O',
                        'p' => 'P',
                        'q' => 'Q',
                        'r' => 'R',
                        's' => 'S',
                        't' => 'T',
                        'u' => 'U',
                        'v' => 'V',
                        'w' => 'W',
                        'x' => 'X',
                        'y' => 'Y',
                        'z' => 'Z',
                        else => c,
                    };
                }

                pub fn send(m: *@This(), comptime msg_tag: anytype, args: anytype) !void {
                    const mod_ptr: *Self.Mods() = @alignCast(@fieldParentPtr(Mods(), @tagName(module_tag), m));
                    const world = @fieldParentPtr(Self, "mod", mod_ptr);

                    // Convert module_tag=.engine_renderer msg_tag=.render_now to "engineRendererRenderNow"
                    comptime var str: []const u8 = "";
                    comptime {
                        var next_upper = false;
                        inline for (@tagName(module_tag)) |c| {
                            if (c == '_') {
                                next_upper = true;
                            } else if (next_upper) {
                                str = str ++ [1]u8{upper(c)};
                                next_upper = false;
                            } else {
                                str = str ++ [1]u8{c};
                            }
                        }
                        next_upper = true;
                        inline for (@tagName(msg_tag)) |c| {
                            if (c == '_') {
                                next_upper = true;
                            } else if (next_upper) {
                                str = str ++ [1]u8{upper(c)};
                                next_upper = false;
                            } else {
                                str = str ++ [1]u8{c};
                            }
                        }
                    }
                    return world.sendStr(str, args);
                }

                /// Returns a new entity.
                pub fn newEntity(m: *@This()) !EntityID {
                    const mod_ptr: *Self.Mods() = @alignCast(@fieldParentPtr(Mods(), @tagName(module_tag), m));
                    const world = @fieldParentPtr(Self, "mod", mod_ptr);
                    return world.entities.new();
                }

                /// Removes an entity.
                pub fn removeEntity(m: *@This(), entity: EntityID) !void {
                    const mod_ptr: *Self.Mods() = @alignCast(@fieldParentPtr(Mods(), @tagName(module_tag), m));
                    const world = @fieldParentPtr(Self, "mod", mod_ptr);
                    try world.entities.removeEntity(entity);
                }
            };
        }

        fn Mods() type {
            var fields: []const StructField = &[0]StructField{};
            inline for (modules.modules) |M| {
                fields = fields ++ [_]std.builtin.Type.StructField{.{
                    .name = @tagName(M.name),
                    .type = Mod(M.name),
                    .default_value = null,
                    .is_comptime = false,
                    .alignment = @alignOf(Mod(M.name)),
                }};
            }
            return @Type(.{
                .Struct = .{
                    .layout = .Auto,
                    .is_tuple = false,
                    .fields = fields,
                    .decls = &[_]std.builtin.Type.Declaration{},
                },
            });
        }

        pub fn init(allocator: mem.Allocator) !Self {
            return Self{
                .allocator = allocator,
                .entities = try Entities(modules.components).init(allocator),
                .mod = undefined,
            };
        }

        pub fn deinit(world: *Self) void {
            world.entities.deinit();
        }

        /// Broadcasts an event to all modules that are subscribed to it.
        ///
        /// The message tag corresponds with the handler method name to be invoked. For example,
        /// if `send(.tick)` is invoked, all modules which declare a `pub fn init` will be invoked.
        ///
        /// Events sent by Mach itself, or the application itself, may be single words. To prevent
        /// name conflicts, events sent by modules provided by a library should prefix their events
        /// with their module name. For example, a module named `.ziglibs_imgui` should use event
        /// names like `.ziglibsImguiClick`, `.ziglibsImguiFoobar`.
        pub fn send(world: *Self, comptime msg_tag: anytype, args: anytype) !void {
            return world.sendStr(@tagName(msg_tag), args);
        }

        pub fn sendStr(world: *Self, comptime msg: anytype, args: anytype) !void {
            // Check for any module that has a handler function named msg (e.g. `fn init` would match "init")
            inline for (modules.modules) |M| {
                if (!@hasDecl(M, msg)) continue;

                // Determine which parameters the handler function wants. e.g.:
                //
                // pub fn init(eng: *mach.Engine) !void
                // pub fn init(eng: *mach.Engine, mach: *mach.Mod(.engine)) !void
                //
                const handler = @field(M, msg);

                // Build a tuple of parameters that we can pass to the function, based on what
                // *mach.Mod(.foo) types it expects as arguments.
                var params: std.meta.ArgsTuple(@TypeOf(handler)) = undefined;
                comptime var argIndex = 0;
                inline for (@typeInfo(@TypeOf(params)).Struct.fields) |param| {
                    comptime var found = false;
                    inline for (@typeInfo(Mods()).Struct.fields) |f| {
                        if (param.type == *f.type) {
                            // TODO: better initialization place for modules
                            @field(@field(world.mod, f.name), "entities") = &world.entities;
                            @field(@field(world.mod, f.name), "allocator") = world.allocator;

                            @field(params, param.name) = &@field(world.mod, f.name);
                            found = true;
                            break;
                        } else if (param.type == *Self) {
                            @field(params, param.name) = world;
                            found = true;
                            break;
                        } else if (param.type == f.type) {
                            @compileError("Module handler " ++ @tagName(M.name) ++ "." ++ msg ++ " should be *T not T: " ++ @typeName(param.type));
                        }
                    }
                    if (!found) {
                        @field(params, param.name) = args[argIndex];
                        argIndex += 1;
                    }
                }

                // Invoke the handler
                try @call(.auto, handler, params);
            }
        }
    };
}
