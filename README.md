# Dr. Driving Lite

A first-person driving game in **x86 assembly language**, inspired by the mobile game *Dr. Driving*.
COAL (Computer Organization and Assembly Language) final project, FAST Lahore.

You sit behind the orange bonnet of your car. In **Level 1** you drive 1000 metres on a three-lane highway, dodging traffic before your time or fuel runs out. In **Level 2** you park the car inside a marked bay without touching the parked cars or the cones.

## Features

**Phase 1: Screen**
- Time bar, distance and score, speed box, fuel bar
- Three-lane perspective road with white lane markings
- Traffic cars, orange bonnet, dashboard and steering wheel

**Phase 2: Highway driving**
- Accelerate, brake gradually, change lanes, reverse (only from 0 km/h)
- Traffic drives towards you in a repeating pattern
- Collisions stop the car and cost 50 points; you can drive on afterwards
- Time and fuel go down; the fuel bar turns red when fuel is low
- Distance grows with speed, and score grows with distance (+10 per metre)
- Level ends at exactly 1000 m (success), or when time or fuel runs out

**Phase 3: Menu and parking**
- Start menu: press **1** for Highway, **2** for Parking
- The game returns to the menu after every level (ENTER, or by itself after 8 s)
- Parking lot with 3 parked cars, 2 cones and a bay marked **P**
- Parking sensor: distance to the nearest object in your lane, with a green, yellow and red light bar
- Banner "PARKING • LEVEL 2"
- You succeed only when the **whole car** is inside the bay, **fully stopped**, and **touching nothing**. You get +10 points for every second left.

## Technologies

| | |
|---|---|
| Language | x86 assembly, 16-bit real mode |
| Assembler | NASM (flat `.com` binary) |
| Runs in | DOSBox |
| Graphics | VGA mode 13h (320 × 200, 256 colours), drawn into an off-screen buffer and then copied to the screen (no flicker) |
| Keyboard | Own INT 9 interrupt handler (knows which keys are held down) |
| Timing | Own INT 8 interrupt handler, timer at ~73 ticks per second, so the game runs at the same speed on every PC |

## How to build and run

1. Install **DOSBox** and put **NASM** (`nasm.exe`) in the folder you mount in DOSBox.
2. Put `drive.asm` in that folder.
3. In DOSBox:
   ```
   mount c C:\path\to\your\folder
   c:
   nasm drive.asm -o drive.com
   drive
   ```
4. **Smooth play:** press **Ctrl+F12** a few times in DOSBox to raise the CPU cycles, or set `cycles=20000` in the DOSBox options file. At the default setting the game still runs at the correct speed but looks jerky.

## Controls

| Key | Action |
|---|---|
| 1 / 2 | Start Highway / Parking (menu only) |
| Up | Accelerate |
| Space | Brake gradually to 0 |
| Left / Right | Move one lane left / right |
| Down | Reverse (only when the car is stopped; never brakes) |
| Enter | Back to the menu after a level ends |
| Esc | Leave a level (to the menu); in the menu: quit to DOS |

## Project structure

Everything is in one file, `drive.asm`, in labelled sections:

| Section | What it does |
|---|---|
| constants | all fixed numbers: colours, layout, speeds, scan codes |
| video | mode 13h, palette, back buffer, flip, lines, rectangles, circles, trapezoids |
| text | 8×8 BIOS font, strings and numbers |
| road | sky, grass, perspective road, lane lines (`PROJ_K / z` projection) |
| cars | one car drawn from behind in perspective |
| traffic | traffic table, repeating movement, far-to-near drawing |
| cockpit | bonnet, dashboard, steering wheel |
| hud | time bar, distance/score, speed box, gear, fuel bar |
| input | INT 9 keyboard handler and `key_down` table |
| timer | INT 8 timer handler and tick counter |
| player | speed, gear D/R, lane changes |
| gauges | distance, score, fuel, time |
| collisions | highway crashes |
| highway | level 1: start, update, end messages, frame |
| menu | game modes, start menu |
| parking | level 2: lot, bay, cars, cones, collisions, success test |
| sensor | parking sensor distance and light bar |
| main program | game loop: update per timer tick, draw, flip |
| data | all variables, tables, texts and the colour palette |

## Team and contributions

| Member | Main work |
|---|---|
| *Qanita Adnan*  | Project setup and graphics base, cockpit, speed box and fuel bar, keyboard handler, accelerate/brake/coast, lane changes, reverse, fuel use, faster text drawing, menu and game modes, parking driving, parking sensor, auto-return and controls help |
| *Salmana Adnan* | Road and perspective, traffic cars, time bar, distance/score, timer handler, distance and score from speed, moving traffic pattern, collisions, level end messages, bonnet table, parking lot, bay and banner, parked cars and cones, parking success test, README |

Both members made the same number of commits in every phase. Tags `phase1`, `phase2` and `phase3` mark the end of each phase.

## Bonus: original Dr. Driving layout (+10)

Press **B** in the menu to switch the layout between **SIMPLE** (Phases 1-3) and **ORIGINAL** (Figures 3 and 4). The game rules are exactly the same in both layouts; only the screen changes.

The original layout adds:
- **Speedometer:** round dial 0-200 km/h with ticks, numbers, a red needle and the speed as digits under the centre
- **Fuel gauge:** round dial from E to F with a needle; the fuel pump icon turns red when fuel is low
- **Lane guide arrows:** panel at the top with one arrow per lane; your lane is highlighted
- **Indicators and hazard:** the green arrows flash for one second when you move one lane to that side; the red hazard triangle stays off
- **Gear box:** bottom left, shows a green D when driving and a red R while reversing
- **Light panel:** 3 x 3 small coloured lights next to the gear box
- **Big steering wheel:** three spokes and a hub with S
- **City street** on the highway (sidewalks and buildings with windows that slide past while you drive)
- **Trees and a fence** behind the parking lot

New code in the `bonus` section of `drive.asm`: `draw_instruments`, `draw_gear_box`, `draw_light_panel`, `sin256` / `cos256` (sine table), `dial_point`, `draw_line` (Bresenham), `draw_speedometer`, `draw_fuel_gauge`, `draw_lane_guide`, `draw_indicators`, `draw_wheel2`, `draw_city`, `vline`, `draw_park_scenery`.

Tip: the original layout draws more, so raise the DOSBox cycles to 20000 or more (Ctrl+F12) for smooth play.

### Fair crashes and traffic from behind
- A crash only counts when you can **see** the car: it must be in your lane and touching your bonnet on the screen. Cars beside you or behind you never cost points.
- When you drive slower than the traffic (40 km/h), cars catch up with you from behind. A car that reaches you in your lane **changes lane and overtakes** you instead of driving through your car. When it comes round the pattern again it gets its normal lane back, so the traffic still repeats.
- A **rear-view mirror** at the top of the highway screen shows the cars behind you (windscreen and yellow headlights).

### More like the original game
- Traffic and parked cars are drawn as real cars seen from behind: roof with rear window, tail lights, white number plate, bumper, wheels and a shadow.
- Original layout: narrow pavement with kerbs, pastel buildings with rows of blue and lit yellow windows and low shop fronts, a shine line on the bonnet, a dashboard edge, and HUD text with a dark shadow so it can be read on the buildings.
