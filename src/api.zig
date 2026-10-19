pub const c = @cImport({
    // Zig 0.16 translate-c cannot translate MinGW's fortified wchar inline
    // wrappers. Import declarations only; Ember never calls those C helpers.
    // This does not rebuild or alter the precompiled SDL runtime libraries.
    if (@import("builtin").os.tag == .windows) @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3_ttf/SDL_ttf.h");
    @cInclude("SDL3_image/SDL_image.h");
    @cInclude("libretro.h");
});
