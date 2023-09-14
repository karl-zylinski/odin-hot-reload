package game

import "core:fmt"

// All the state of our game will live within this struct. In order for the hot
// reload to work all the memory that the game uses must be transferrable from
// one game DLL to the next when a hot reload occurs, which we can do when
// all the game's memory live in here.
GameMemory :: struct {
    some_state: int,
}

g_mem: ^GameMemory

// This function dynamically allocates a block of memory that we’ll use to store
// all the state in our game. We assign it to a global variable so we can use it
// from the other functions.
@(export)
game_init :: proc() {
    g_mem = new(GameMemory)
}

// Here you do your simulation and rendering. Return false when you wish to
// terminate the program.
@(export)
game_update :: proc() -> bool {
    // To try hot reload, have the main program running and recompile
    // the game DLL with -= instead of += below
    g_mem.some_state += 1
    fmt.println(g_mem.some_state)
    return true
}

// This is called by the main program when game_update has returned false and
// the main loop has exited. Clean up your memory here.
@(export)
game_shutdown :: proc() {
    free(g_mem)
}

// Return the pointer to the game memory. When a hot reload occurs, then main
// program needs to get hold of the game memory pointer, so that it can load
// a new game DLL and tell that game DLL to use the same memory by feeding
// game_hot_reloaded with the game memory pointer.
@(export)
game_memory :: proc() -> rawptr {
    return g_mem
}

// Run after a hot reload occurs. When that hot reload occurs a new game DLL
// is loaded and that game DLL needs to use the same game memory as the
// previous game DLL. Therefore this function is fed the GameMemory pointer.
@(export)
game_hot_reloaded :: proc(mem: ^GameMemory) {
    g_mem = mem
}
