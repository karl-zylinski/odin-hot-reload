package game

import "core:dynlib"
import "core:os"

GameAPI :: struct {
	init: proc(),
	update: proc() -> bool,
	shutdown: proc(),
	memory: proc() -> rawptr,

	lib: dynlib.Library,
	lib_write_time: u64,
	api_version: int,
}

load_game_api :: proc(api_version: int, lib_write_time: u64) -> (GameAPI, bool) {
	game_dll_name := fmt.tprintf("game_{0}.dll", api_version)

	if libc.system(fmt.ctprintf("copy game.dll {0}", game_dll_name)) != 0 {
		fmt.println("Failed to copy game.dll to {0}", game_dll_name)
		return {}, false
	}

	lib, lib_ok := dynlib.load_library(game_dll_name)

	if !lib_ok {
		fmt.println("Failed to load game library")
		return {}, false
	}

	return GameAPI {
		init = cast(proc())(dynlib.symbol_address(lib, "init") or_else nil),
		update = cast(proc() -> bool)(dynlib.symbol_address(lib, "update") or_else nil),
		shutdown = cast(proc())(dynlib.symbol_address(lib, "shutdown") or_else nil),
		memory := cast(proc() -> rawptr)(dynlib.symbol_address(lib, "memory") or_else nil)

		lib = lib,
		lib_write_time = lib_write_time,
		api_version = api_version,
	}, true
}

unload_game_api :: proc(api: GameAPI) {
	if api.lib != nil {
		dynlib.unload_library(api.lib)
	}

	if libc.system(fmt.ctprintf("del game_{0}.dll", api.api_version)) != 0 {
		fmt.println("Failed to remove game_{0}.dll copy", api.api_version)
	}
}

main :: proc() {
	game_api_version := 0
	game_api, game_api_ok := load_game_api(game_api_version)

	if !game_api_ok {
		fmt.println("Failed to load Game API")
		return
	}

	game_api_version += 1
	game_api.init()

	for {
		if game_api.update() == false {
			break
		}

		last_game_write, last_game_write_err := os.last_write_time_by_name("game.dll")

		if last_game_write_err == os.ERROR_NONE && game_api.lib_write_time != last_game_write {
			new_game_api, new_game_api_ok := load_game_api(game_api_version, last_game_write)
			
			if new_game_api_ok {
				game_memory := game_api.memory()
				unload_game_api(game_api)
				game_api = new_game_api
				game_api.hot_reloaded(game_memory)
				game_api_version += 1
			}
		}
	}

	game_api.shutdown()
	unload_game_api(game_api)
}