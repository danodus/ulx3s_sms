;==============================================================
; test_sprites
; Five solid sprites, plus the same tiles on the name table.
;
; Mode 4 notes (SMS):
;   R6 bit 2 = 0  -> sprite patterns at VRAM $0000 (value $FB)
;   CRAM $00-$0F  -> background palette
;   CRAM $10-$1F  -> sprite palette
;   Tile bytes    -> 8 rows of (plane0, plane1, plane2, plane3)
;==============================================================
.memorymap
defaultslot 0
slotsize $8000
slot 0 $0000
.endme

.rombankmap
bankstotal 1
banksize $8000
banks 1
.endro

.sdsctag 1.2,"Sprite Test","SMS sprite drawing test","ulx3s_sms"

.bank 0 slot 0
.org $0000
    di
    im 1
    jp main

.org $0066
    retn

main:
    ld sp, $dff0

    ld hl, VdpData
    ld b, VdpDataEnd - VdpData
    ld c, $bf
    otir

    ; Clear VRAM. A must be reloaded: the loop uses it for the zero test.
    ld a, $00
    out ($bf), a
    ld a, $40
    out ($bf), a
    ld bc, $4000
ClearVRAM:
    xor a
    out ($be), a
    dec bc
    ld a, b
    or c
    jp nz, ClearVRAM

    ; Background palette at CRAM $00
    ld a, $00
    out ($bf), a
    ld a, $c0
    out ($bf), a
    ld hl, PaletteData
    ld b, PaletteDataEnd - PaletteData
    ld c, $be
    otir

    ; Sprite palette at CRAM $10 (not $20 — CRAM is only 32 bytes)
    ld a, $10
    out ($bf), a
    ld a, $c0
    out ($bf), a
    ld hl, PaletteData
    ld b, PaletteDataEnd - PaletteData
    ld c, $be
    otir

    ; Patterns at $0000. R6=$FB selects this block for sprites.
    ; Mode 4 backgrounds always use $0000 as well.
    ld a, $00
    out ($bf), a
    ld a, $40
    out ($bf), a
    ld hl, TileData
    ld bc, TileDataEnd - TileData
LoadTiles:
    ld a, (hl)
    inc hl
    out ($be), a
    dec bc
    ld a, b
    or c
    jp nz, LoadTiles

    ; Blank name table (tile 0). Backdrop colour then shows through.
    ld a, $00
    out ($bf), a
    ld a, $78          ; $3800 | $40
    out ($bf), a
    ld bc, $0600
FillName:
    xor a
    out ($be), a
    dec bc
    ld a, b
    or c
    jp nz, FillName

    ; Top row: tiles 1..5, so the patterns are visible as background too.
    ld a, $00
    out ($bf), a
    ld a, $78          ; $3800 | $40
    out ($bf), a
    ld hl, NameTableRow
    ld b, NameTableRowEnd - NameTableRow
    ld c, $be
    otir

    ; SAT Y bytes (100 bytes at $3F00, matching the BIOS)
    ld a, $00
    out ($bf), a
    ld a, $7f          ; $3F00 | $40
    out ($bf), a
    ld hl, SpriteY
    ld b, SpriteYEnd - SpriteY
    ld c, $be
    otir

    ; SAT X + pattern (128 bytes at $3F80)
    ld a, $80
    out ($bf), a
    ld a, $7f          ; $3F80 | $40
    out ($bf), a
    ld hl, SpriteXP
    ld b, SpriteXPEnd - SpriteXP
    ld c, $be
    otir

    ; Display on, 8x8 sprites
    ld a, %11000010
    out ($bf), a
    ld a, $81
    out ($bf), a

Forever:
    jp Forever

;==============================================================
; Data
;==============================================================

; Same as hello_world, except R6 = $FB (sprite patterns in the low 8KB)
VdpData:
.db $04,$80,$00,$81,$ff,$82,$ff,$85,$fb,$86,$00,$87,$00,$88,$00,$89,$ff,$8a
VdpDataEnd:

; 00BBGGRR. Colour 0 is the backdrop. Sprite colour 0 stays transparent.
PaletteData:
.db $10,$03,$0c,$3c,$0f,$33,$30,$3f
.db $00,$00,$00,$00,$00,$00,$00,$00
PaletteDataEnd:

; Tile 0 blank. Tiles 1-5 are solid 8x8 blocks, colours 1-5.
TileData:
.dsb 32, $00
.db $ff,$00,$00,$00, $ff,$00,$00,$00, $ff,$00,$00,$00, $ff,$00,$00,$00
.db $ff,$00,$00,$00, $ff,$00,$00,$00, $ff,$00,$00,$00, $ff,$00,$00,$00
.db $00,$ff,$00,$00, $00,$ff,$00,$00, $00,$ff,$00,$00, $00,$ff,$00,$00
.db $00,$ff,$00,$00, $00,$ff,$00,$00, $00,$ff,$00,$00, $00,$ff,$00,$00
.db $ff,$ff,$00,$00, $ff,$ff,$00,$00, $ff,$ff,$00,$00, $ff,$ff,$00,$00
.db $ff,$ff,$00,$00, $ff,$ff,$00,$00, $ff,$ff,$00,$00, $ff,$ff,$00,$00
.db $00,$00,$ff,$00, $00,$00,$ff,$00, $00,$00,$ff,$00, $00,$00,$ff,$00
.db $00,$00,$ff,$00, $00,$00,$ff,$00, $00,$00,$ff,$00, $00,$00,$ff,$00
.db $ff,$00,$ff,$00, $ff,$00,$ff,$00, $ff,$00,$ff,$00, $ff,$00,$ff,$00
.db $ff,$00,$ff,$00, $ff,$00,$ff,$00, $ff,$00,$ff,$00, $ff,$00,$ff,$00
TileDataEnd:

; Name-table words: tile index, attributes
NameTableRow:
.dw $0001,$0002,$0003,$0004,$0005
NameTableRowEnd:

; Y is the line above the sprite. $D0 terminates the list.
SpriteY:
.db 30,31,32,33,34,35,36,37,38,39,$d0
;.dsb 94, $00
SpriteYEnd:

SpriteXP:
.db 0,2, 10,4, 20,2, 30,4, 40,2, 50,4, 60,2, 70,4, 80,2, 90,4 100,2, 110,4
;.dsb 118, $00
SpriteXPEnd:
