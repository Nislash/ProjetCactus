use godot::prelude::*;

mod boss_ai;

struct CactusExtension;

#[gdextension]
unsafe impl ExtensionLibrary for CactusExtension {}

#[derive(GodotClass)]
#[class(init, base=Node)]
struct CactusBoot {
    base: Base<Node>,
}

#[godot_api]
impl INode for CactusBoot {
    fn ready(&mut self) {
        godot_print!("[Rust] Hello from gdext — CactusBoot is ready");
    }
}
