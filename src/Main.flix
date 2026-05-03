def main(): Unit \ {IO, Chan, NonDet} =
    if (GameEngine.ensureMainThread()) ()
    else {
        let config: GameEngine.EngineConfig = {
            screenWidth = Game.screenWi(),
            screenHeight = Game.screenHi(),
            title = "Flappy Bird",
            textureManifest =
                // Background
                {name = "background_day", path = "sprites/background_day.png", hasAlpha = true} ::
                // Bird
                {name = "bird_orange_0", path = "sprites/bird_orange_0.png", hasAlpha = true} ::
                {name = "bird_orange_1", path = "sprites/bird_orange_1.png", hasAlpha = true} ::
                {name = "bird_orange_2", path = "sprites/bird_orange_2.png", hasAlpha = true} ::
                // Pipes
                {name = "pipe_green_top", path = "sprites/pipe_green_top.png", hasAlpha = true} ::
                {name = "pipe_green_bottom", path = "sprites/pipe_green_bottom.png", hasAlpha = true} ::
                // Ground
                {name = "ground", path = "sprites/ground.png", hasAlpha = true} ::
                // Numbers (middle)
                {name = "number_middle_0", path = "sprites/number_middle_0.png", hasAlpha = true} ::
                {name = "number_middle_1", path = "sprites/number_middle_1.png", hasAlpha = true} ::
                {name = "number_middle_2", path = "sprites/number_middle_2.png", hasAlpha = true} ::
                {name = "number_middle_3", path = "sprites/number_middle_3.png", hasAlpha = true} ::
                {name = "number_middle_4", path = "sprites/number_middle_4.png", hasAlpha = true} ::
                {name = "number_middle_5", path = "sprites/number_middle_5.png", hasAlpha = true} ::
                {name = "number_middle_6", path = "sprites/number_middle_6.png", hasAlpha = true} ::
                {name = "number_middle_7", path = "sprites/number_middle_7.png", hasAlpha = true} ::
                {name = "number_middle_8", path = "sprites/number_middle_8.png", hasAlpha = true} ::
                {name = "number_middle_9", path = "sprites/number_middle_9.png", hasAlpha = true} ::
                // Labels
                {name = "label_flappy_bird", path = "sprites/label_flappy_bird.png", hasAlpha = true} ::
                {name = "label_game_over", path = "sprites/label_game_over.png", hasAlpha = true} ::
                {name = "label_new", path = "sprites/label_new.png", hasAlpha = true} ::
                // UI
                {name = "instructions", path = "sprites/instructions.png", hasAlpha = true} ::
                {name = "panel_score", path = "sprites/panel_score.png", hasAlpha = true} ::
                {name = "button_play_normal", path = "sprites/button_play_normal.png", hasAlpha = true} ::
                {name = "button_play_pressed", path = "sprites/button_play_pressed.png", hasAlpha = true} ::
                {name = "button_pause", path = "sprites/button_pause.png", hasAlpha = true} ::
                {name = "button_resume", path = "sprites/button_resume.png", hasAlpha = true} ::
                {name = "button_menu", path = "sprites/button_menu.png", hasAlpha = true} ::
                {name = "button_score_normal", path = "sprites/button_score_normal.png", hasAlpha = true} ::
                {name = "button_score_pressed", path = "sprites/button_score_pressed.png", hasAlpha = true} ::
                {name = "button_rate_normal", path = "sprites/button_rate_normal.png", hasAlpha = true} ::
                {name = "button_rate_pressed", path = "sprites/button_rate_pressed.png", hasAlpha = true} ::
                // Medals
                {name = "medal_bronze", path = "sprites/medal_bronze.png", hasAlpha = true} ::
                {name = "medal_gold", path = "sprites/medal_gold.png", hasAlpha = true} ::
                {name = "medal_platinum", path = "sprites/medal_platinum.png", hasAlpha = true} ::
                {name = "medal_silver", path = "sprites/medal_silver.png", hasAlpha = true} ::
                // Spark
                {name = "spark_0", path = "sprites/spark_0.png", hasAlpha = true} ::
                {name = "spark_1", path = "sprites/spark_1.png", hasAlpha = true} ::
                {name = "spark_2", path = "sprites/spark_2.png", hasAlpha = true} ::
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
            clearColor = {r = 0.392f32, g = 0.584f32, b = 0.929f32},
            maxDeltaTime = 0.05
        };
       
        run {
            Game.start(GameEngine.Game.getFontAtlas("default"))
        } with LwjglLayer.withLwjgl(config)
          with Math.Random.runWithIO
          with Fs.FileRead.runWithIO
          with Fs.FileWrite.runWithIO
          with Fs.Glob.runWithIO
          with Fs.ModificationTime.runWithFileTime
          with Fs.FileTime.runWithIO
    }
