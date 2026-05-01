def main(): Unit \ IO =
    if (GameEngine.ensureMainThread()) ()
    else {
        let config: GameEngine.EngineConfig = {
            screenWidth = Game.screenWi(),
            screenHeight = Game.screenHi(),
            title = "Flappy Bird",
            textureManifest =
                // Backgrounds
                {name = "background_day", path = "sprites/background_day.png", hasAlpha = true} ::
                {name = "background_night", path = "sprites/background_night.png", hasAlpha = true} ::
                // Bird (orange)
                {name = "bird_orange_0", path = "sprites/bird_orange_0.png", hasAlpha = true} ::
                {name = "bird_orange_1", path = "sprites/bird_orange_1.png", hasAlpha = true} ::
                {name = "bird_orange_2", path = "sprites/bird_orange_2.png", hasAlpha = true} ::
                // Bird (blue)
                {name = "bird_blue_0", path = "sprites/bird_blue_0.png", hasAlpha = true} ::
                {name = "bird_blue_1", path = "sprites/bird_blue_1.png", hasAlpha = true} ::
                {name = "bird_blue_2", path = "sprites/bird_blue_2.png", hasAlpha = true} ::
                // Bird (red)
                {name = "bird_red_0", path = "sprites/bird_red_0.png", hasAlpha = true} ::
                {name = "bird_red_1", path = "sprites/bird_red_1.png", hasAlpha = true} ::
                {name = "bird_red_2", path = "sprites/bird_red_2.png", hasAlpha = true} ::
                // Pipes
                {name = "pipe_green_top", path = "sprites/pipe_green_top.png", hasAlpha = true} ::
                {name = "pipe_green_bottom", path = "sprites/pipe_green_bottom.png", hasAlpha = true} ::
                {name = "pipe_red_top", path = "sprites/pipe_red_top.png", hasAlpha = true} ::
                {name = "pipe_red_bottom", path = "sprites/pipe_red_bottom.png", hasAlpha = true} ::
                // Ground
                {name = "ground", path = "sprites/ground.png", hasAlpha = true} ::
                // Numbers (large)
                {name = "number_large_0", path = "sprites/number_large_0.png", hasAlpha = true} ::
                {name = "number_large_1", path = "sprites/number_large_1.png", hasAlpha = true} ::
                {name = "number_large_2", path = "sprites/number_large_2.png", hasAlpha = true} ::
                {name = "number_large_3", path = "sprites/number_large_3.png", hasAlpha = true} ::
                {name = "number_large_4", path = "sprites/number_large_4.png", hasAlpha = true} ::
                {name = "number_large_5", path = "sprites/number_large_5.png", hasAlpha = true} ::
                {name = "number_large_6", path = "sprites/number_large_6.png", hasAlpha = true} ::
                {name = "number_large_7", path = "sprites/number_large_7.png", hasAlpha = true} ::
                {name = "number_large_8", path = "sprites/number_large_8.png", hasAlpha = true} ::
                {name = "number_large_9", path = "sprites/number_large_9.png", hasAlpha = true} ::
                // Labels
                {name = "label_flappy_bird", path = "sprites/label_flappy_bird.png", hasAlpha = true} ::
                {name = "label_game_over", path = "sprites/label_game_over.png", hasAlpha = true} ::
                {name = "label_get_ready", path = "sprites/label_get_ready.png", hasAlpha = true} ::
                // UI
                {name = "instructions", path = "sprites/instructions.png", hasAlpha = true} ::
                {name = "panel_score", path = "sprites/panel_score.png", hasAlpha = true} ::
                {name = "button_play_normal", path = "sprites/button_play_normal.png", hasAlpha = true} ::
                {name = "button_ok", path = "sprites/button_ok.png", hasAlpha = true} ::
                Nil,
            fontManifest =
                {name = "default", path = "fonts/font_score.ttf", fontSize = 60.0} ::
                Nil,
            soundManifest =
                {name = "sfx_wing", path = "audio/sfx_wing.wav", looping = false} ::
                {name = "sfx_point", path = "audio/sfx_point.wav", looping = false} ::
                {name = "sfx_hit", path = "audio/sfx_hit.wav", looping = false} ::
                {name = "sfx_die", path = "audio/sfx_die.wav", looping = false} ::
                {name = "sfx_swooshing", path = "audio/sfx_swooshing.wav", looping = false} ::
                Nil,
            clearColor = {r = 0.0f32, g = 0.0f32, b = 0.0f32}
        };
       
        Math.Random.runWithIO(_ ->
            run {
                Game.start(GameEngine.Game.getFontAtlas("default"))
            } with LwjglLayer.withLwjgl(config)
        )
    }
