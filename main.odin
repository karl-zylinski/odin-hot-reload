package game

import "core:dynlib"
import "core:os"
import "core:fmt"
import "core:c/libc"

// The main program will load a game DLL and each frame check if it changed.
// If it does change then it will load a new game DLL and use the code in that
// DLL instead. It will give the new DLL the memory the old one used.
main :: proc() {
	// We use this to number the loaded game DLL. It is incremented on each
	// game DLL reload. Whenever we load the game API the game DLL is copied
	// so we can load it without locking the original game.dll.
	game_api_version := 0
	game_api, game_api_ok := load_game_api(game_api_version)

	if !game_api_ok {
		fmt.println("Failed to load Game API")
		return
	}

	game_api_version += 1

	// Tell the game to start itself up!
	game_api.init()

	// same as while(true) in C
	for {
		// The update function of the game will update and render the game.
		// It should return false when we want to exit the program and break
		// the main loop.
		if game_api.update() == false {
			break
		}

		// Check the last write date of the game DLL. If the date is different
		// from the one on the current game API, then try to do a hot reload.
		last_game_write, last_game_write_err := os.last_write_time_by_name("game.dll")

		if last_game_write_err == os.ERROR_NONE && game_api.lib_write_time != last_game_write {
			// Load a new game API. Might sometimes fail due game.dll still
			// being written by the Odin compiler. In that case new_game_api_ok
			// will be false and we will trey again next frame.
			new_game_api, new_game_api_ok := load_game_api(game_api_version)
			
			if new_game_api_ok {
				// This fetches a pointer to the game memory in the OLD game DLL
				game_memory := game_api.memory()

				// Completely unload the game DLL. The game memory survives,
				// that memory will only be deallocated if we explicitly free it
				unload_game_api(game_api)

				// Replace the game_api with the new one, this will make update
				// use the new game API next frame.
				game_api = new_game_api

				// Tell the new game API to use the same game memory
				game_api.hot_reloaded(game_memory)

				// Bump the API version
				game_api_version += 1
			}
		}
	}

	// This will finally deallocate game memory and do other cleanup.
	game_api.shutdown()
	
	unload_game_api(game_api)
}

// This struct contains pointers to the different procedures that live in the
// game DLL, see the game.odin code for docs on what they do.
GameAPI :: struct {
	init: proc(),
	update: proc() -> bool,
	shutdown: proc(),
	memory: proc() -> rawptr,
	hot_reloaded: proc(rawptr),

	lib: dynlib.Library,

	// We use this in the main loop to know if the game DLL has been updated
	// and needs reloading.
	lib_write_time: os.File_Time,
	api_version: int,
}

load_game_api :: proc(api_version: int) -> (GameAPI, bool) {
	lib_last_write, lib_last_write_err := os.last_write_time_by_name("game.dll")

	if lib_last_write_err != os.ERROR_NONE {
		fmt.println("Could not fetch last write date of game.dll")
		return {}, false
	}

	// We cannot just load the game DLL directly. This would lock the game DLL
	// and you could no longer hot reload since the compiler can't write to
	// the game DLL. So we make a unique name based on api_version (a number
	// that is incremented for each DLL reload) and then copy the DLL to that
	// location.
	game_dll_name := fmt.tprintf("game_{0}.dll", api_version)

	// This quite often fails on the first attempt because our program tries
	// to copy it before the odin compiler has finished writing it. In that
	// case we will return and try again the next frame.
	//
	// Note: Here I use windows copy command, it's not the best solution, but
	// it is the most compact code for this sample.
	if libc.system(fmt.ctprintf("copy game.dll {0}", game_dll_name)) != 0 {
		fmt.println("Failed to copy game.dll to {0}", game_dll_name)
		return {}, false
	}

	// This loads the newly copied game DLL
	lib, lib_ok := dynlib.load_library(game_dll_name)

	if !lib_ok {
		fmt.println("Failed to load game library")
		return {}, false
	}

	// Fetches all those procedures we marked with @(export) inside the game DLL
	// Not that it needs to manually cast them to the correct signature.
	api := GameAPI {
		init = cast(proc())(dynlib.symbol_address(lib, "game_init") or_else nil),
		update = cast(proc() -> bool)(dynlib.symbol_address(lib, "game_update") or_else nil),
		shutdown = cast(proc())(dynlib.symbol_address(lib, "game_shutdown") or_else nil),
		memory = cast(proc() -> rawptr)(dynlib.symbol_address(lib, "game_memory") or_else nil),
		hot_reloaded = cast(proc(rawptr))(dynlib.symbol_address(lib, "game_hot_reloaded") or_else nil),

		lib = lib,
		lib_write_time = lib_last_write,
		api_version = api_version,
	}

	if api.init == nil || api.update == nil || api.shutdown == nil || api.memory == nil || api.hot_reloaded == nil {
		dynlib.unload_library(api.lib)
		fmt.println("Game DLL is missing required procedure")
		return {}, false
	}

	return api, true
}

unload_game_api :: proc(api: GameAPI) {
	if api.lib != nil {
		dynlib.unload_library(api.lib)
	}

	// Delete the copied game DLL.
	//
	// Note: Here I use windows copy command, it's not the best solution, but
	// it is the most compact code for this sample.
	if libc.system(fmt.ctprintf("del game_{0}.dll", api.api_version)) != 0 {
		fmt.println("Failed to remove game_{0}.dll copy", api.api_version)
	}
}