package game

// This is your main game state memory blob.
GameMemory :: struct {
	some_state: int,
}

g_mem: ^GameMemory

// Run at the start of program, creates the main game memory
@(export)
init :: proc() {
	g_mem = new(GameMemory)
}

// Here you do your simulation and rendering.
@(export)
update :: proc() -> bool {
	g_mem.some_state += 1
	fmt.println(g_mem.some_state)
}

// Shutdown the whole game.
@(export)
shutdown :: proc() {
	free(g_mem)
}

// Return the pointer to the memory, used when hot reloading to reuse
// the same memory blob.
@(export)
memory :: proc() -> rawptr {
	return g_mem
}

// Run after a hot reload occurs. Gives us back our memory!
@(export)
hot_reloaded :: proc(mem: ^GameMemory) {
	g_mem = mem
}
