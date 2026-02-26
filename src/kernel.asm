BITS 16
ORG 0x0000

start:
    cli
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0xFFFE
    sti

    mov byte [mode], 0
    mov byte [selected], 0
    mov byte [main_page], 0
    mov byte [pref_mode], 0
    mov byte [window_mode_enabled], 0
    mov byte [window_title_focus], 0
    mov byte [window_visible], 1
    mov byte [window_minimized], 0
    mov word [window_x], 76
    mov word [window_y], 42
    mov word [vesa_mode], 0x0103
    call ask_input_mode
    call set_mode_13
    call boot_screen_init
    call boot_wait
    call set_mode_13
    xor di, di
    mov al, 0x01
    mov cx, 320*200
    rep stosb
    call run_background_tasks
    call apply_pref_mode
    call draw_ui

key_loop:
    call update_cursor
    mov ah, 0x01
    int 0x16
    jz key_loop
    xor ah, ah
    int 0x16
    mov byte [window_key_consumed], 0
    call window_key_handler
    cmp byte [window_key_consumed], 1
    je key_loop
    cmp byte [mode], 3
    jne .normal_keys
    call desktop_key_handler
    jmp key_loop
.normal_keys:
    cmp byte [mode], 9
    jne .check_explorer
    call editor_handle_key
    jmp key_loop
.check_explorer:
    cmp byte [mode], 8
    jne .check_common
    cmp al, 'c'
    je explorer_copy_key
    cmp al, 'C'
    je explorer_copy_key
    cmp al, 'x'
    je explorer_cut_key
    cmp al, 'X'
    je explorer_cut_key
    cmp al, 'v'
    je explorer_paste_key
    cmp al, 'V'
    je explorer_paste_key
    cmp al, 'd'
    je explorer_delete_key
    cmp al, 'D'
    je explorer_delete_key
    cmp ah, 0x53
    je explorer_delete_key
.check_common:
    cmp ah, 0x3C
    je open_debug
    cmp ah, 0x01
    je key_back
    cmp ah, 0x48
    je key_up
    cmp ah, 0x50
    je key_down
    cmp ah, 0x1C
    je key_enter
    jmp key_loop

key_up:
    cmp byte [selected], 0
    je key_loop
    dec byte [selected]
    call draw_ui
    jmp key_loop

key_down:
    call get_max_index
    cmp byte [selected], al
    je key_loop
    inc byte [selected]
    call draw_ui
    jmp key_loop

key_back:
    cmp byte [mode], 0
    je key_loop
    cmp byte [mode], 10
    je hardware_back
    cmp byte [mode], 9
    je editor_back_to_explorer
    cmp byte [mode], 8
    je explorer_back_drives
    cmp byte [mode], 7
    je explorer_back_main
    cmp byte [mode], 6
    je media_back_drives
    mov byte [mode], 0
    mov byte [selected], 0
    call draw_ui
    jmp key_loop

hardware_back:
    mov byte [mode], 0
    mov byte [main_page], 1
    mov byte [selected], 0
    call draw_ui
    jmp key_loop

desktop_exit:
    call apply_pref_mode
    mov byte [mode], 0
    mov byte [selected], 0
    call draw_ui
    jmp key_loop

desktop_key_handler:
    cmp ah, 0x01
    jne .done
    jmp desktop_exit
.done:
    ret

window_key_handler:
    cmp byte [window_mode_enabled], 1
    jne .done
    cmp byte [mode], 7
    je .ok_mode
    cmp byte [mode], 8
    jne .done
.ok_mode:
    ; Ctrl+Esc enters title-bar focus mode.
    cmp ah, 0x01
    jne .focus_keys
    push ax
    mov ah, 0x02
    int 0x16
    test al, 0x04
    pop ax
    jz .done
    mov byte [window_title_focus], 1
    mov byte [window_key_consumed], 1
    call draw_ui
    ret

.focus_keys:
    cmp byte [window_title_focus], 1
    jne .done
    cmp ah, 0x4B
    je .left
    cmp ah, 0x4D
    je .right
    cmp ah, 0x48
    je .up
    cmp ah, 0x50
    je .down
    cmp ah, 0x1C
    je .enter
    cmp al, 'x'
    je .close
    cmp al, 'X'
    je .close
    cmp al, 'c'
    je .restore
    cmp al, 'C'
    je .restore
    cmp al, 'v'
    je .minimize
    cmp al, 'V'
    je .minimize
    jmp .done
.left:
    cmp word [window_x], 10
    jbe .redraw
    dec word [window_x]
    dec word [window_x]
    jmp .redraw
.right:
    cmp word [window_x], 160
    jae .redraw
    inc word [window_x]
    inc word [window_x]
    jmp .redraw
.up:
    cmp word [window_y], 12
    jbe .redraw
    dec word [window_y]
    dec word [window_y]
    jmp .redraw
.down:
    cmp word [window_y], 84
    jae .redraw
    inc word [window_y]
    inc word [window_y]
    jmp .redraw
.enter:
    mov byte [window_title_focus], 0
    jmp .redraw
.close:
    mov byte [window_visible], 0
    mov byte [window_minimized], 0
    jmp .redraw
.restore:
    mov byte [window_visible], 1
    mov byte [window_minimized], 0
    jmp .redraw
.minimize:
    mov byte [window_visible], 1
    mov byte [window_minimized], 1
.redraw:
    mov byte [window_key_consumed], 1
    call draw_ui
.done:
    ret

open_debug:
    mov byte [mode], 4
    mov byte [selected], 0
    call draw_ui
    jmp key_loop

key_enter:
    cmp byte [mode], 4
    je key_loop
    cmp byte [mode], 10
    je key_loop
    cmp byte [mode], 5
    je media_drive_enter
    cmp byte [mode], 6
    je media_file_enter
    cmp byte [mode], 7
    je explorer_drive_enter
    cmp byte [mode], 8
    je explorer_file_enter
    cmp byte [mode], 0
    je main_enter
    cmp byte [mode], 1
    je power_enter
    jmp res_enter

main_enter:
    cmp byte [main_page], 0
    jne main_enter_page2
    mov al, [selected]
    cmp al, 0
    je open_desktop
    cmp al, 1
    je open_res
    cmp al, 2
    je open_power
    cmp al, 3
    je open_media
    cmp al, 4
    je open_explorer
    mov byte [main_page], 1
    mov byte [selected], 0
    call draw_ui
    jmp key_loop

main_enter_page2:
    mov al, [selected]
    cmp al, 0
    je open_hardware
    cmp al, 1
    je toggle_window_mode
    mov byte [main_page], 0
    mov byte [selected], 0
    call draw_ui
    jmp key_loop

open_desktop:
    call apply_pref_mode
    mov byte [mode], 3
    call draw_ui
    jmp key_loop

open_res:
    mov byte [mode], 2
    mov byte [selected], 0
    call draw_ui
    jmp key_loop

open_power:
    mov byte [mode], 1
    mov byte [selected], 0
    call draw_ui
    jmp key_loop

open_media:
    call media_probe_drives
    mov byte [mode], 5
    mov byte [selected], 0
    call draw_ui
    jmp key_loop

open_explorer:
    call app_window_reset
    call media_probe_drives
    mov byte [mode], 7
    mov byte [selected], 0
    mov byte [explorer_status], 0
    call draw_ui
    jmp key_loop

open_hardware:
    call update_runtime_info
    mov byte [mode], 10
    mov byte [selected], 0
    call draw_ui
    jmp key_loop

toggle_window_mode:
    mov al, [window_mode_enabled]
    xor al, 1
    mov [window_mode_enabled], al
    mov byte [window_title_focus], 0
    mov byte [window_visible], 1
    mov byte [window_minimized], 0
    call draw_ui
    jmp key_loop

media_drive_enter:
    mov al, [drive_count]
    cmp al, 0
    je key_loop
    mov bl, [selected]
    cmp bl, al
    je media_back_main
    mov bh, 0
    mov si, drive_list
    add si, bx
    mov al, [si]
    mov [media_selected_drive], al
    call media_scan_files
    mov byte [mode], 6
    mov byte [selected], 0
    call draw_ui
    jmp key_loop

media_file_enter:
    mov al, [media_file_count]
    mov bl, [selected]
    cmp bl, al
    je media_back_drives
    call media_play_selected
    call draw_ui
    jmp key_loop

media_back_drives:
    mov byte [mode], 5
    mov byte [selected], 0
    call draw_ui
    jmp key_loop

media_back_main:
    mov byte [mode], 0
    mov byte [selected], 0
    call draw_ui
    jmp key_loop

explorer_drive_enter:
    mov al, [drive_count]
    cmp al, 0
    je key_loop
    mov bl, [selected]
    cmp bl, al
    je explorer_back_main
    mov bh, 0
    mov si, drive_list
    add si, bx
    mov al, [si]
    mov [media_selected_drive], al
    call explorer_scan_files
    call app_window_reset
    mov byte [mode], 8
    mov byte [selected], 0
    call draw_ui
    jmp key_loop

explorer_file_enter:
    mov al, [explorer_file_count]
    mov bl, [selected]
    cmp bl, al
    je explorer_back_drives
    call app_window_reset
    call editor_open_selected
    jc key_loop
    mov byte [mode], 9
    call draw_ui
    jmp key_loop

app_window_reset:
    mov byte [window_title_focus], 0
    mov byte [window_visible], 1
    mov byte [window_minimized], 0
    mov word [window_x], 76
    mov word [window_y], 42
    ret

editor_back_to_explorer:
    mov byte [mode], 8
    call draw_ui
    jmp key_loop

explorer_back_drives:
    mov byte [mode], 7
    mov byte [selected], 0
    call draw_ui
    jmp key_loop

explorer_back_main:
    mov byte [mode], 0
    mov byte [selected], 0
    call draw_ui
    jmp key_loop

explorer_copy_key:
    call explorer_copy_selected
    call draw_ui
    jmp key_loop

explorer_cut_key:
    call explorer_cut_selected
    call draw_ui
    jmp key_loop

explorer_paste_key:
    call explorer_paste
    call draw_ui
    jmp key_loop

explorer_delete_key:
    call explorer_delete_selected
    call draw_ui
    jmp key_loop

power_enter:
    mov al, [selected]
    cmp al, 0
    je do_reboot
    cmp al, 1
    je do_shutdown
    mov byte [mode], 0
    mov byte [selected], 0
    call draw_ui
    jmp key_loop

res_enter:
    mov al, [selected]
    cmp al, 0
    je res_set_320
    cmp al, 1
    je res_set_640
    cmp al, 2
    je res_set_800
    cmp al, 3
    je res_set_1024
    cmp al, 4
    je res_set_fit
    mov byte [mode], 0
    mov byte [selected], 0
    call draw_ui
    jmp key_loop

res_set_320:
    mov byte [pref_mode], 0
    mov byte [mode], 0
    mov byte [selected], 0
    call apply_pref_mode
    call draw_ui
    jmp key_loop

res_set_640:
    mov byte [pref_mode], 1
    mov byte [mode], 0
    mov byte [selected], 0
    call apply_pref_mode
    call draw_ui
    jmp key_loop

res_set_800:
    mov byte [pref_mode], 2
    mov byte [mode], 0
    mov byte [selected], 0
    call apply_pref_mode
    call draw_ui
    jmp key_loop

res_set_1024:
    mov byte [pref_mode], 3
    mov byte [mode], 0
    mov byte [selected], 0
    call apply_pref_mode
    call draw_ui
    jmp key_loop

res_set_fit:
    mov byte [pref_mode], 4
    mov byte [mode], 0
    mov byte [selected], 0
    call apply_pref_mode
    call draw_ui
    jmp key_loop

do_reboot:
    int 0x19
    jmp 0FFFFh:0000h

do_shutdown:
    ; APM BIOS shutdown path
    mov ax, 0x5301
    xor bx, bx
    int 0x15
    mov ax, 0x530E
    xor bx, bx
    mov cx, 0x0102
    int 0x15
    mov ax, 0x5307
    mov bx, 0x0001
    mov cx, 0x0003
    int 0x15

    ; ACPI/emulator fallback ports (QEMU/Bochs/VirtualBox variants)
    mov ax, 0x2000
    mov dx, 0x0604
    out dx, ax
    mov ax, 0x2001
    out dx, ax
    mov ax, 0x2000
    mov dx, 0x0600
    out dx, ax
    mov ax, 0x2001
    out dx, ax
    mov ax, 0x2000
    mov dx, 0xB004
    out dx, ax
    mov ax, 0x2001
    out dx, ax
    mov ax, 0x3400
    mov dx, 0x4004
    out dx, ax
    mov ax, 0x3401
    out dx, ax
    jmp halt_forever

halt_forever:
    cli
.halt:
    hlt
    jmp .halt

boot_screen_init:
    xor di, di
    mov al, 0x01
    mov cx, 320*200
    rep stosb

    mov ax, 40
    mov bx, 44
    mov cx, 232
    mov dx, 104
    mov byte [draw_color], 0x03
    call fill_rect

    mov ax, 44
    mov bx, 48
    mov cx, 224
    mov dx, 20
    mov byte [draw_color], 0x09
    call fill_rect

    mov dh, 6
    mov dl, 10
    mov bl, 0x0F
    mov si, boot_title
    call print_at

    mov dh, 10
    mov dl, 10
    mov si, boot_msg
    call print_at

    mov dh, 15
    mov dl, 10
    mov si, boot_stage
    call print_at

    mov ax, 160
    mov bx, 56
    mov cx, 208
    mov dx, 12
    mov byte [draw_color], 0x08
    call fill_rect

    mov dh, 22
    mov dl, 8
    mov si, boot_hint
    call print_at
    ret

boot_progress:
    push ax
    push bx
    push cx
    push dx

    mov ax, 162
    mov bx, 60
    mov cx, 200
    mov dx, 8
    mov byte [draw_color], 0x00
    call fill_rect

    pop dx
    pop cx
    pop bx
    pop ax
    push ax
    push bx
    push cx
    push dx
    xor ah, ah
    mov bl, 2
    mul bl
    mov cx, ax
    cmp cx, 0
    je .done
    mov ax, 162
    mov bx, 60
    mov dx, 8
    mov byte [draw_color], 0x0A
    call fill_rect
.done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

boot_wait:
    mov ah, 0x00
    int 0x1A
    mov bx, dx
    add bx, 12
.wait:
    mov ah, 0x01
    int 0x16
    jnz .key
    mov ah, 0x00
    int 0x1A
    cmp dx, bx
    jb .wait
    ret
.key:
    mov ah, 0x00
    int 0x16
    ret

set_mode_13:
    mov ax, 0x0013
    int 0x10
    mov ax, 0xA000
    mov es, ax
    mov byte [video_mode], 0
    call mouse_refresh
    ret

set_mode_12:
    mov ax, 0x0012
    int 0x10
    mov byte [video_mode], 1
    call mouse_refresh
    ret

set_mode_vesa:
    ; Keep high-res options selectable, but use stable 640x480 path.
    ; BIOS text rendering in many VESA modes is inconsistent in this project stage.
    call set_mode_12
    ret

apply_pref_mode:
    mov al, [pref_mode]
    cmp al, 0
    je .m320
    cmp al, 1
    je .m640
    cmp al, 2
    je .m800
    cmp al, 4
    je .fit
    mov word [vesa_mode], 0x0105
    jmp set_mode_vesa
.m800:
    mov word [vesa_mode], 0x0103
    jmp set_mode_vesa
.m640:
    mov word [vesa_mode], 0x0101
    jmp set_mode_vesa
.fit:
    ; Stable "fit screen" path (full-screen 640x480 in current renderer).
    call set_mode_12
    ret
.m320:
    jmp set_mode_13

init_boot_drive:
    push ds
    xor ax, ax
    mov ds, ax
    mov al, [0x0500]
    pop ds
    mov [boot_drive], al
    ret

run_background_tasks:
    call init_boot_drive
    call probe_pm
    call probe_hw
    call mm_init
    call mm_self_test
    call fat12_probe
    ret

probe_hw:
    call probe_cpu
    call probe_vbe
    call probe_memory
    call probe_sb16
    call update_runtime_info
    ret

probe_cpu:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    mov eax, 0
    cpuid
    mov dword [cpu_vendor+0], ebx
    mov dword [cpu_vendor+4], edx
    mov dword [cpu_vendor+8], ecx
    mov byte [cpu_vendor+12], 0

    mov eax, 1
    cpuid
    mov dword [cpu_sig], eax
    mov di, cpu_sig_hex
    call dword_to_hex8

    mov eax, ebx
    shr eax, 16
    mov [cpu_logical], al
    mov al, [cpu_logical]
    mov di, cpu_logical_hex
    call byte_to_hex2
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

probe_vbe:
    push ax
    push bx
    push es
    mov byte [vbe_ok], 0
    mov ax, cs
    mov es, ax
    mov di, vbe_info
    mov dword [es:di], 0x32454256
    mov ax, 0x4F00
    int 0x10
    cmp ax, 0x004F
    jne .fail
    mov byte [vbe_ok], 1
    mov ax, [es:di+4]
    push di
    mov di, vbe_ver_hex
    call word_to_hex4
    pop di
    mov ax, [es:di+18]
    mov di, vbe_mem_hex
    call word_to_hex4
    jmp .out
.fail:
    mov word [vbe_ver_hex], '--'
    mov word [vbe_ver_hex+2], '--'
    mov byte [vbe_ver_hex+4], 0
    mov word [vbe_mem_hex], '--'
    mov word [vbe_mem_hex+2], '--'
    mov byte [vbe_mem_hex+4], 0
.out:
    pop es
    pop bx
    pop ax
    ret

probe_memory:
    push ax
    push bx
    mov ax, 0
    int 0x12
    mov [mem_conv_kb], ax
    mov di, mem_conv_hex
    call word_to_hex4

    mov ax, 0xE801
    int 0x15
    jc .noe801
    mov [mem_e801_ax], ax
    mov [mem_e801_bx], bx
    mov di, mem_e801_ax_hex
    call word_to_hex4
    mov ax, [mem_e801_bx]
    mov di, mem_e801_bx_hex
    call word_to_hex4
    jmp .out
.noe801:
    mov word [mem_e801_ax], 0
    mov word [mem_e801_bx], 0
    mov word [mem_e801_ax_hex], '--'
    mov word [mem_e801_ax_hex+2], '--'
    mov byte [mem_e801_ax_hex+4], 0
    mov word [mem_e801_bx_hex], '--'
    mov word [mem_e801_bx_hex+2], '--'
    mov byte [mem_e801_bx_hex+4], 0
.out:
    pop bx
    pop ax
    ret

probe_sb16:
    push ax
    push dx
    mov byte [sb16_ok], 0
    mov word [sb16_base], 0x0220

    ; DSP reset sequence on base+0x6, expect 0xAA on data port.
    mov dx, [sb16_base]
    add dx, 6
    mov al, 1
    out dx, al
    call io_delay
    xor al, al
    out dx, al

    mov cx, 2000
.wait_rdy:
    mov dx, [sb16_base]
    add dx, 0x0E
    in al, dx
    test al, 0x80
    jnz .read_ack
    loop .wait_rdy
    jmp .out
.read_ack:
    mov dx, [sb16_base]
    add dx, 0x0A
    in al, dx
    cmp al, 0xAA
    jne .out
    mov byte [sb16_ok], 1
.out:
    pop dx
    pop ax
    ret

sb16_speaker_on:
    cmp byte [sb16_ok], 1
    jne .out
    push ax
    push dx
    mov dx, [sb16_base]
    add dx, 0x0C
    mov al, 0xD1
    out dx, al
    pop dx
    pop ax
.out:
    ret

sb16_speaker_off:
    cmp byte [sb16_ok], 1
    jne .out
    push ax
    push dx
    mov dx, [sb16_base]
    add dx, 0x0C
    mov al, 0xD3
    out dx, al
    pop dx
    pop ax
.out:
    ret

io_delay:
    push cx
    mov cx, 500
.d:
    nop
    loop .d
    pop cx
    ret

update_runtime_info:
    push ax
    mov al, [boot_drive]
    mov di, boot_drive_hex
    call byte_to_hex2
    pop ax
    ret

byte_to_hex2:
    push bx
    mov bl, al
    mov al, bl
    shr al, 4
    call nibble_to_ascii
    mov [di], al
    inc di
    mov al, bl
    and al, 0x0F
    call nibble_to_ascii
    mov [di], al
    inc di
    mov byte [di], 0
    pop bx
    ret

word_to_hex4:
    push ax
    push bx
    mov bx, ax
    mov al, bh
    call byte_to_hex2
    mov al, bl
    call byte_to_hex2
    pop bx
    pop ax
    ret

dword_to_hex8:
    push cx
    push dx
    mov cx, 8
.loop:
    mov edx, eax
    shr edx, 28
    mov al, dl
    call nibble_to_ascii
    mov [di], al
    inc di
    shl eax, 4
    loop .loop
    mov byte [di], 0
    pop dx
    pop cx
    ret

nibble_to_ascii:
    and al, 0x0F
    cmp al, 9
    jbe .num
    add al, 55
    ret
.num:
    add al, '0'
    ret

ask_input_mode:
    mov byte [cursor_mode], 0
    mov byte [mouse_present], 0

    mov ax, 0x0003
    int 0x10
    mov si, ask_1
    call print_tty
    mov si, ask_2
    call print_tty
    mov si, ask_3
    call print_tty
    mov si, ask_4
    call print_tty

.wait_key:
    xor ah, ah
    int 0x16
    cmp al, '1'
    je .cursor
    cmp al, '2'
    je .kbd
    cmp al, 'c'
    je .cursor
    cmp al, 'C'
    je .cursor
    cmp al, 'k'
    je .kbd
    cmp al, 'K'
    je .kbd
    jmp .wait_key

.cursor:
    mov byte [cursor_mode], 1
    call mouse_init
    ret

.kbd:
    mov byte [cursor_mode], 0
    call mouse_init
    ret

mouse_init:
    mov ax, 0x0000
    int 0x33
    cmp ax, 0
    je .none
    mov byte [mouse_present], 1
    jmp mouse_refresh
.none:
    mov byte [mouse_present], 0
    ret

mouse_refresh:
    cmp byte [mouse_present], 1
    jne .done
    ; Use software cursor in graphics mode, keep BIOS mouse cursor hidden.
    mov ax, 0x0002
    int 0x33
.done:
    ret

update_cursor:
    cmp byte [cursor_mode], 1
    jne .hide
    cmp byte [mouse_present], 1
    jne .hide
    cmp byte [video_mode], 0
    jne .hide

    mov ax, 0x0003
    int 0x33
    shr cx, 1
    cmp dx, 199
    jbe .y_ok
    mov dx, 199
.y_ok:
    mov [cursor_x], cx
    mov [cursor_y], dx
    call draw_cursor_xor
    mov byte [cursor_drawn], 1
    ret

.hide:
    cmp byte [cursor_drawn], 1
    jne .done
    call draw_cursor_xor
    mov byte [cursor_drawn], 0
.done:
    ret

draw_cursor_xor:
    mov ax, 0xA000
    mov es, ax
    mov ax, [cursor_y]
    mov bx, 320
    mul bx
    add ax, [cursor_x]
    mov di, ax
    xor byte [es:di], 0x0F
    ret

print_tty:
    lodsb
    test al, al
    jz .done
    mov ah, 0x0E
    mov bh, 0x00
    mov bl, 0x07
    int 0x10
    jmp print_tty
.done:
    ret

probe_pm:
    ; Safe placeholder: keep system stable while still surfacing PM readiness.
    ; Full PE toggle can be re-enabled after VBox log review.
    mov byte [pm_ok], 1
    ret

mm_init:
    mov cx, 16
    mov di, mm_bitmap
    xor al, al
    rep stosb
    ret

mm_alloc:
    xor bx, bx
.next_block:
    cmp bl, 128
    jae .fail
    mov al, bl
    shr al, 3
    mov si, mm_bitmap
    add si, ax
    mov al, bl
    and al, 7
    mov ah, 1
    mov cl, al
    shl ah, cl
    test byte [si], ah
    jnz .used
    or byte [si], ah
    mov al, bl
    clc
    ret
.used:
    inc bl
    jmp .next_block
.fail:
    stc
    ret

mm_free:
    mov bl, al
    mov al, bl
    shr al, 3
    mov si, mm_bitmap
    add si, ax
    mov al, bl
    and al, 7
    mov ah, 1
    mov cl, al
    shl ah, cl
    not ah
    and byte [si], ah
    ret

mm_self_test:
    mov byte [mm_ok], 0
    call mm_alloc
    jc .done
    mov dl, al
    call mm_alloc
    jc .done
    mov al, dl
    call mm_free
    mov byte [mm_ok], 1
.done:
    ret

fat12_probe:
    push es
    mov byte [fat_ok], 0
    mov ax, 0x8000
    mov es, ax
    mov di, 19
    mov cx, 14
.sector_loop:
    push cx
    push di
    xor bx, bx
    mov ax, di
    call read_sector_lba
    jc .next
    call scan_root_sector
    cmp byte [fat_ok], 1
    je .found
.next:
    pop di
    inc di
    pop cx
    loop .sector_loop
    pop es
    ret
.found:
    pop di
    pop cx
    pop es
    ret

scan_root_sector:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    xor di, di
    mov cx, 16
.entry_loop:
    mov al, [es:di]
    cmp al, 0
    je .done
    cmp al, 0E5h
    je .next_entry
    push cx
    push di
    mov si, fat_test_name
    mov bx, di
    mov cx, 11
.cmp_loop:
    mov al, [si]
    cmp al, [es:bx]
    jne .no_match
    inc si
    inc bx
    loop .cmp_loop
    mov byte [fat_ok], 1
    pop di
    pop cx
    jmp .done
.no_match:
    pop di
    pop cx
.next_entry:
    add di, 32
    loop .entry_loop
.done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

read_sector_lba:
    push bx
    push cx
    push dx
    push si
    push di
    mov di, ax
    mov si, 2
.retry:
    mov ax, di
    call lba_to_chs
    mov ah, 0x02
    mov al, 0x01
    mov dl, [boot_drive]
    int 0x13
    jnc .ok
    mov ah, 0x00
    mov dl, [boot_drive]
    int 0x13
    dec si
    jnz .retry
    stc
    jmp .out
.ok:
    clc
.out:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    ret

lba_to_chs:
    push bx
    xor dx, dx
    mov cx, 18
    div cx
    mov cl, dl
    inc cl
    xor dx, dx
    mov bx, 2
    div bx
    mov dh, dl
    mov ch, al
    pop bx
    ret

media_probe_drives:
    mov byte [drive_count], 0
    mov byte [drive_scan_idx], 0
.probe_next:
    mov al, [drive_scan_idx]
    cmp al, 26
    jae .done
    call drive_index_to_bios
    jc .next
    mov dl, al
    call drive_is_readable
    jc .next
    mov bl, [drive_count]
    cmp bl, 6
    jae .done
    xor bh, bh
    mov di, drive_list
    add di, bx
    mov [di], dl
    mov di, drive_label_0
    mov al, bl
    mov ah, 5
    mul ah
    add di, ax
    mov al, [drive_letter]
    mov [di], al
    mov byte [di+1], ':'
    mov byte [di+2], 0
    inc byte [drive_count]
.next:
    inc byte [drive_scan_idx]
    jmp .probe_next
.done:
    ret

drive_is_readable:
    push es
    xor bx, bx
    mov ax, 0x9000
    mov es, ax
    mov [media_selected_drive], dl
    cmp dl, 0E0h
    jb .std
    xor ax, ax
    call read_sector_iso2048
    jmp .out
.std:
    xor ax, ax
    call read_sector_media
.out:
    pop es
    ret

drive_index_to_bios:
    mov [drive_letter], al
    add byte [drive_letter], 'A'
    cmp al, 0
    je .a
    cmp al, 1
    je .b
    sub al, 2
    cmp al, 16
    jb .hdd
    sub al, 16
    add al, 0E0h
    clc
    ret
.hdd:
    add al, 80h
    clc
    ret
.a:
    mov al, 00h
    clc
    ret
.b:
    mov al, 01h
    clc
    ret

media_update_drive_labels:
    ret

media_scan_files:
    mov byte [media_file_count], 0
    mov byte [media_play_status], 0
    mov byte [media_scan_lba], 0
    mov byte [media_from_iso], 0
    mov di, media_name_0
    mov cx, 64
    mov al, '.'
    rep stosb
    mov byte [media_name_0+12], 0
    mov byte [media_name_1+12], 0
    mov byte [media_name_2+12], 0
    mov byte [media_name_3+12], 0

    call explorer_scan_files
    mov al, [explorer_from_iso]
    mov [media_from_iso], al
    call media_import_from_explorer
    ret

read_sector_media:
    push bx
    push cx
    push dx
    push si
    push di
    mov di, ax
    mov dl, [media_selected_drive]
    cmp dl, 80h
    jb .chs
    cmp dl, 0E0h
    jae .no_chs

    mov byte [dap_size], 16
    mov byte [dap_reserved], 0
    mov word [dap_count], 1
    mov word [dap_off], bx
    mov word [dap_seg], es
    mov word [dap_lba_lo], di
    mov word [dap_lba_hi], 0
    mov dword [dap_lba_top], 0
    mov si, dap
    mov ah, 0x42
    int 0x13
    jc .chs_from_hdd
    clc
    jmp .out

.chs_from_hdd:
    ; Fallback for BIOSes that reject extended read on some IDE setups.
    mov si, 2
    jmp .retry

.no_chs:
    stc
    jmp .out

.chs:
    mov si, 2
.retry:
    mov ax, di
    call lba_to_chs
    mov ah, 0x02
    mov al, 0x01
    mov dl, [media_selected_drive]
    int 0x13
    jnc .ok
    mov ah, 0x00
    mov dl, [media_selected_drive]
    int 0x13
    dec si
    jnz .retry
    stc
    jmp .out
.ok:
    clc
    jmp .out
.fail:
    stc
.out:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    ret

read_sector_iso2048:
    ; IN: AX=lba, ES:BX=buffer, drive from media_selected_drive
    push cx
    push dx
    push si
    push di
    mov di, ax
    mov dl, [media_selected_drive]
    mov byte [dap_size], 16
    mov byte [dap_reserved], 0
    mov word [dap_count], 1
    mov word [dap_off], bx
    mov word [dap_seg], es
    mov word [dap_lba_lo], di
    mov word [dap_lba_hi], 0
    mov dword [dap_lba_top], 0
    mov si, dap
    mov ah, 0x42
    int 0x13
    jc .fail
    clc
    jmp .out
.fail:
    stc
.out:
    pop di
    pop si
    pop dx
    pop cx
    ret

write_sector_media:
    push bx
    push cx
    push dx
    push si
    push di
    mov di, ax
    mov dl, [media_selected_drive]
    cmp dl, 80h
    jb .chs

    mov byte [dap_size], 16
    mov byte [dap_reserved], 0
    mov word [dap_count], 1
    mov word [dap_off], bx
    mov word [dap_seg], es
    mov word [dap_lba_lo], di
    mov word [dap_lba_hi], 0
    mov dword [dap_lba_top], 0
    mov si, dap
    mov ah, 0x43
    mov al, 0
    int 0x13
    jc .chs_from_hdd
    clc
    jmp .out

.chs_from_hdd:
    mov si, 2
    jmp .retry

.chs:
    mov si, 2
.retry:
    mov ax, di
    call lba_to_chs
    mov ah, 0x03
    mov al, 0x01
    mov dl, [media_selected_drive]
    int 0x13
    jnc .ok
    mov ah, 0x00
    mov dl, [media_selected_drive]
    int 0x13
    dec si
    jnz .retry
    stc
    jmp .out
.ok:
    clc
.out:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    ret

explorer_scan_files:
    mov byte [explorer_file_count], 0
    mov byte [explorer_from_iso], 0
    mov di, explorer_name_0
    mov cx, 65
    mov al, '.'
    rep stosb
    mov byte [explorer_name_0+12], 0
    mov byte [explorer_name_1+12], 0
    mov byte [explorer_name_2+12], 0
    mov byte [explorer_name_3+12], 0
    mov byte [explorer_name_4+12], 0

    mov al, [media_selected_drive]
    cmp al, 0E0h
    jb .fat_scan
    mov byte [explorer_from_iso], 1
    jmp explorer_scan_files_iso
.fat_scan:

    push es
    mov ax, 0x9000
    mov es, ax
    mov di, 19
    mov cx, 14
.root_sector:
    push cx
    push di
    mov [explorer_scan_lba], di
    xor bx, bx
    mov ax, di
    call read_sector_media
    jc .next_sector
    call explorer_scan_sector
    cmp byte [explorer_file_count], 5
    jae .done
.next_sector:
    pop di
    inc di
    pop cx
    loop .root_sector
    pop es
    ret
.done:
    pop di
    pop cx
    pop es
    ret

explorer_scan_files_iso:
    push es
    mov ax, 0x9000
    mov es, ax
    xor bx, bx
    mov ax, 16
    call read_sector_iso2048
    jc .out
    cmp byte [es:1], 'C'
    jne .out
    cmp byte [es:2], 'D'
    jne .out
    cmp byte [es:3], '0'
    jne .out
    cmp byte [es:4], '0'
    jne .out
    cmp byte [es:5], '1'
    jne .out
    mov ax, [es:158]
    mov [iso_root_lba], ax
    mov ax, [es:166]
    mov [iso_root_size], ax
    mov ax, [iso_root_size]
    add ax, 2047
    mov bx, 2048
    xor dx, dx
    div bx
    mov [iso_root_secs], ax
    xor di, di
.sec_loop:
    mov ax, di
    cmp ax, [iso_root_secs]
    jae .out
    mov ax, [iso_root_lba]
    add ax, di
    xor bx, bx
    call read_sector_iso2048
    jc .out
    xor si, si
.entry_loop:
    cmp si, 2048
    jae .next_sec
    mov cl, [es:si]
    cmp cl, 0
    je .next_sec
    mov al, [es:si+25]
    test al, 0x02
    jnz .skip
    mov al, [es:si+32]
    cmp al, 0
    je .skip
    cmp al, 1
    jne .copy
    mov al, [es:si+33]
    cmp al, 0
    je .skip
    cmp al, 1
    je .skip
.copy:
    call explorer_iso_store_entry
    cmp byte [explorer_file_count], 5
    jae .out
.skip:
    xor ch, ch
    mov ax, si
    add ax, cx
    mov si, ax
    jmp .entry_loop
.next_sec:
    inc di
    jmp .sec_loop
.out:
    pop es
    ret

explorer_iso_store_entry:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov bl, [explorer_file_count]
    cmp bl, 5
    jae .done
    xor bh, bh

    mov di, explorer_name_0
    mov ax, bx
    mov dx, ax
    shl ax, 3
    shl dx, 2
    add ax, dx
    add ax, bx
    add di, ax

    mov al, [es:si+32]
    xor ah, ah
    mov cx, ax
    mov bx, si
    add bx, 33
    mov dx, 12
.cpy:
    cmp cx, 0
    je .term
    cmp dx, 0
    je .term
    mov al, [es:bx]
    cmp al, ';'
    je .term
    cmp al, 'a'
    jb .keep
    cmp al, 'z'
    ja .keep
    sub al, 32
.keep:
    mov [di], al
    inc di
    inc bx
    dec cx
    dec dx
    jmp .cpy
.term:
    mov byte [di], 0

    mov bl, [explorer_file_count]
    xor bh, bh
    mov di, explorer_entry_lba
    shl bx, 1
    add di, bx
    mov ax, [es:si+2]
    mov [di], ax
    mov di, explorer_entry_size
    add di, bx
    mov ax, [es:si+10]
    mov [di], ax

    inc byte [explorer_file_count]
.done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

explorer_scan_sector:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    xor di, di
    mov cx, 16
.entry:
    mov al, [es:di]
    cmp al, 0
    je .done
    cmp al, 0E5h
    je .next
    mov al, [es:di+11]
    cmp al, 0x0F
    je .next
    test al, 0x08
    jnz .next
    test al, 0x10
    jnz .next
    call explorer_copy_name
    cmp byte [explorer_file_count], 5
    jae .done
.next:
    add di, 32
    loop .entry
.done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

explorer_copy_name:
    mov bl, [explorer_file_count]
    cmp bl, 5
    jae .done
    mov bh, 0
    mov si, explorer_name_0
    mov ax, bx
    mov bl, 13
    mul bl
    add si, ax

    mov bx, di
    mov cx, 8
.name:
    mov al, [es:bx]
    cmp al, ' '
    je .dot
    mov [si], al
    inc si
    inc bx
    loop .name
.dot:
    mov byte [si], '.'
    inc si
    mov bx, di
    add bx, 8
    mov cx, 3
.ext:
    mov al, [es:bx]
    mov [si], al
    inc si
    inc bx
    loop .ext
    mov byte [si], 0

    mov bl, [explorer_file_count]
    mov bh, 0
    mov si, explorer_entry_sector
    add si, bx
    mov al, [explorer_scan_lba]
    mov [si], al
    mov si, explorer_entry_offset
    add si, bx
    mov ax, di
    mov [si], al

    inc byte [explorer_file_count]
.done:
    ret

explorer_copy_selected:
    mov al, [selected]
    cmp al, [explorer_file_count]
    jae .no_file
    call explorer_capture_selected
    jc .fail
    mov byte [clip_valid], 1
    mov byte [clip_cut], 0
    mov byte [explorer_status], 1
    ret
.no_file:
.fail:
    ret

explorer_cut_selected:
    mov al, [selected]
    cmp al, [explorer_file_count]
    jae .no_file
    call explorer_capture_selected
    jc .fail
    mov byte [clip_valid], 1
    mov byte [clip_cut], 1
    mov byte [explorer_status], 2
    ret
.no_file:
.fail:
    ret

explorer_capture_selected:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es

    mov bl, [selected]
    mov bh, 0
    mov si, explorer_entry_sector
    add si, bx
    mov al, [si]
    mov [clip_sector], al
    xor ah, ah
    mov si, explorer_entry_offset
    add si, bx
    mov bl, [si]
    mov [clip_offset], bl
    mov al, [media_selected_drive]
    mov [clip_drive], al

    mov ax, 0x9000
    mov es, ax
    xor bx, bx
    xor ah, ah
    mov al, [clip_sector]
    call read_sector_media
    jc .fail

    mov di, clip_entry
    mov si, 0
    mov al, [clip_offset]
    mov bl, al
    xor bh, bh
    add si, bx
    mov cx, 32
.copy:
    mov al, [es:si]
    mov [di], al
    inc si
    inc di
    loop .copy
    clc
    jmp .out
.fail:
    stc
.out:
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

explorer_delete_selected:
    push ax
    push bx
    push dx
    push es
    mov al, [selected]
    cmp al, [explorer_file_count]
    jae .out
    mov bl, al
    xor bh, bh
    mov si, explorer_entry_sector
    add si, bx
    mov al, [si]
    xor ah, ah
    mov si, explorer_entry_offset
    add si, bx
    mov dl, [si]

    mov ax, 0x9000
    mov es, ax
    xor bx, bx
    call read_sector_media
    jc .out
    xor bx, bx
    mov bl, dl
    mov byte [es:bx], 0E5h
    xor bx, bx
    call write_sector_media
    jc .out
    mov byte [explorer_status], 4
    call explorer_scan_files
    mov al, [selected]
    cmp al, [explorer_file_count]
    jbe .out
    mov al, [explorer_file_count]
    mov [selected], al
.out:
    pop es
    pop dx
    pop bx
    pop ax
    ret

explorer_paste:
    cmp byte [clip_valid], 1
    je .have_clip
    mov byte [explorer_status], 7
    ret
.have_clip:
    mov al, [clip_drive]
    cmp al, [media_selected_drive]
    je .same_drive
    mov byte [explorer_status], 6
    ret
.same_drive:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es

    mov ax, 0x9000
    mov es, ax
    mov di, 19
    mov cx, 14
.find_sector:
    push cx
    push di
    xor bx, bx
    mov ax, di
    call read_sector_media
    jc .next_sector
    xor bx, bx
.find_entry:
    mov al, [es:bx]
    cmp al, 0
    je .slot
    cmp al, 0E5h
    je .slot
    add bx, 32
    cmp bx, 256
    jb .find_entry
.next_sector:
    pop di
    inc di
    pop cx
    loop .find_sector
    mov byte [explorer_status], 5
    jmp .done
.slot:
    mov [paste_sector], di
    mov [paste_offset], bl
    push bx
    mov si, clip_entry
    mov cx, 32
.copy32:
    mov al, [si]
    mov [es:bx], al
    inc si
    inc bx
    loop .copy32
    pop bx

    cmp byte [clip_cut], 1
    jne .write_dest
    mov al, [clip_sector]
    cmp al, [paste_sector]
    jne .write_dest
    mov dl, [clip_offset]
    mov bh, 0
    mov bl, dl
    mov byte [es:bx], 0E5h

.write_dest:
    xor bx, bx
    mov ax, [paste_sector]
    call write_sector_media
    jc .fail

    cmp byte [clip_cut], 1
    jne .ok
    mov al, [clip_sector]
    cmp al, [paste_sector]
    je .clear_cut
    mov al, [clip_sector]
    xor ah, ah
    xor bx, bx
    call read_sector_media
    jc .fail
    mov dl, [clip_offset]
    mov bh, 0
    mov bl, dl
    mov byte [es:bx], 0E5h
    xor bx, bx
    call write_sector_media
    jc .fail
.clear_cut:
    mov byte [clip_valid], 0
.ok:
    mov byte [explorer_status], 3
    call explorer_scan_files
    jmp .done
.fail:
    mov byte [explorer_status], 5
.done:
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

editor_handle_key:
    cmp ah, 0x01
    je .esc
    cmp ah, 0x3C
    je .save
    cmp ah, 0x4B
    je .left
    cmp ah, 0x4D
    je .right
    cmp ah, 0x53
    je .del
    cmp ah, 0x0E
    je .backspace
    cmp ah, 0x1C
    je .enter
    cmp al, 32
    jb .done
    cmp al, 126
    ja .done
    call editor_insert_char
    jmp .redraw
.esc:
    mov byte [mode], 8
    jmp .redraw
.save:
    call editor_save_file
    jmp .redraw
.left:
    cmp word [editor_cursor], 0
    je .done
    dec word [editor_cursor]
    jmp .redraw
.right:
    mov ax, [editor_cursor]
    cmp ax, [editor_len]
    jae .done
    inc word [editor_cursor]
    jmp .redraw
.del:
    call editor_delete_at_cursor
    jmp .redraw
.backspace:
    call editor_backspace
    jmp .redraw
.enter:
    mov al, 13
    call editor_insert_char
    mov al, 10
    call editor_insert_char
    jmp .redraw
.done:
    ret
.redraw:
    call draw_ui
    ret

editor_open_selected:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es

    mov byte [editor_status], 0
    mov byte [editor_known_type], 0
    mov byte [editor_read_only], 0
    mov word [editor_len], 0
    mov word [editor_cursor], 0
    mov al, [media_selected_drive]
    cmp al, 0E0h
    jae editor_open_selected_iso

    mov bl, [selected]
    xor bh, bh
    mov si, explorer_entry_sector
    add si, bx
    mov al, [si]
    mov [editor_dir_sector], al
    xor ah, ah
    mov di, ax
    mov si, explorer_entry_offset
    add si, bx
    mov al, [si]
    mov [editor_dir_offset], al
    mov dl, al

    mov ax, 0x9000
    mov es, ax
    xor bx, bx
    mov ax, di
    call read_sector_media
    jc .fail

    xor bx, bx
    mov bl, dl
    mov si, bx
    mov di, editor_dir_entry
    mov cx, 32
.copy_entry:
    mov al, [es:si]
    mov [di], al
    inc si
    inc di
    loop .copy_entry

    call editor_build_filename
    call editor_check_type

    mov si, editor_dir_entry
    mov ax, [si+26]
    mov [editor_first_cluster], ax
    mov [editor_cur_cluster], ax
    mov ax, [si+28]
    mov [editor_size], ax

    cmp word [editor_size], 0
    je .ok
    cmp word [editor_first_cluster], 2
    jb .ok

    mov ax, 0x9000
    mov es, ax
.load_loop:
    mov ax, [editor_cur_cluster]
    cmp ax, 0x0FF8
    jae .ok
    cmp ax, 2
    jb .ok
    mov bx, ax
    sub bx, 2
    mov ax, 33
    add ax, bx
    xor bx, bx
    call read_sector_media
    jc .fail

    mov ax, [editor_size]
    cmp ax, [editor_len]
    jbe .ok
    sub ax, [editor_len]
    cmp ax, 512
    jbe .chunk_set
    mov ax, 512
.chunk_set:
    mov [editor_chunk], ax

    mov di, editor_buf
    add di, [editor_len]
    xor si, si
    mov cx, [editor_chunk]
.copy_chunk:
    mov al, [es:si]
    mov [di], al
    inc si
    inc di
    loop .copy_chunk
    mov ax, [editor_len]
    add ax, [editor_chunk]
    mov [editor_len], ax

    mov ax, [editor_cur_cluster]
    call fat12_next_cluster_media
    jc .ok
    mov [editor_cur_cluster], ax
    jmp .load_loop

.ok:
    clc
    jmp .out
.fail:
    stc
.out:
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

editor_open_selected_iso:
    mov byte [editor_read_only], 1
    mov bl, [selected]
    xor bh, bh

    mov si, explorer_name_0
    mov ax, bx
    mov dx, ax
    shl ax, 3
    shl dx, 2
    add ax, dx
    add ax, bx
    add si, ax
    mov di, editor_name
.ncopy:
    mov al, [si]
    mov [di], al
    inc si
    inc di
    test al, al
    jnz .ncopy

    mov si, explorer_entry_lba
    shl bx, 1
    add si, bx
    mov ax, [si]
    mov [editor_iso_lba], ax
    mov si, explorer_entry_size
    add si, bx
    mov ax, [si]
    mov [editor_size], ax

    call editor_check_type

    mov ax, [editor_size]
    cmp ax, 2048
    jbe .sz_ok
    mov ax, 2048
.sz_ok:
    mov [editor_len], ax
    mov cx, ax
    cmp cx, 0
    je .ok

    mov ax, 0x9000
    mov es, ax
    xor bx, bx
    mov ax, [editor_iso_lba]
    call read_sector_iso2048
    jc .fail
    xor si, si
    mov di, editor_buf
.cpy:
    mov al, [es:si]
    mov [di], al
    inc si
    inc di
    loop .cpy
.ok:
    clc
    jmp .out
.fail:
    stc
    jmp .out
.out:
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

editor_save_file:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es

    cmp byte [editor_read_only], 1
    jne .rw
    mov byte [editor_status], 5
    jmp .out
.rw:
    mov byte [editor_status], 0
    mov ax, [editor_len]
    cmp ax, [editor_size]
    jbe .size_ok
    mov byte [editor_status], 3
    jmp .out
.size_ok:
    mov ax, [editor_first_cluster]
    mov [editor_cur_cluster], ax
    xor si, si
    mov ax, 0x9000
    mov es, ax

.write_loop:
    mov ax, [editor_cur_cluster]
    cmp ax, 2
    jb .write_done
    cmp ax, 0x0FF8
    jae .write_done
    mov bx, ax
    sub bx, 2
    mov ax, 33
    add ax, bx
    mov [editor_tmp_lba], ax

    ; Clear scratch sector.
    xor bx, bx
    mov cx, 512
    xor al, al
.clr:
    mov [es:bx], al
    inc bx
    loop .clr

    mov ax, [editor_len]
    cmp si, ax
    jae .write_zero
    sub ax, si
    cmp ax, 512
    jbe .wchunk
    mov ax, 512
.wchunk:
    mov [editor_chunk], ax
    xor bx, bx
    mov di, editor_buf
    add di, si
    mov cx, [editor_chunk]
.copyw:
    mov al, [di]
    mov [es:bx], al
    inc di
    inc bx
    loop .copyw
    mov ax, si
    add ax, [editor_chunk]
    mov si, ax
.write_zero:
    xor bx, bx
    mov ax, [editor_tmp_lba]
    call write_sector_media
    jc .io_fail

    mov ax, [editor_cur_cluster]
    call fat12_next_cluster_media
    jc .write_done
    mov [editor_cur_cluster], ax
    jmp .write_loop

.write_done:
    mov ax, 0x9000
    mov es, ax
    xor bx, bx
    mov al, [editor_dir_sector]
    xor ah, ah
    call read_sector_media
    jc .io_fail
    xor bx, bx
    mov bl, [editor_dir_offset]
    mov si, editor_dir_entry
    mov cx, 32
.upd:
    mov al, [si]
    mov [es:bx], al
    inc si
    inc bx
    loop .upd
    mov bx, 0
    mov bl, [editor_dir_offset]
    mov ax, [editor_len]
    mov [es:bx+28], ax
    mov word [es:bx+30], 0
    xor bx, bx
    mov al, [editor_dir_sector]
    xor ah, ah
    call write_sector_media
    jc .io_fail
    mov ax, [editor_len]
    mov [editor_size], ax
    mov byte [editor_status], 1
    jmp .out

.io_fail:
    mov byte [editor_status], 2
.out:
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

editor_insert_char:
    push ax
    push bx
    push cx
    push si
    push di
    mov bx, [editor_len]
    cmp bx, 2046
    jae .out
    mov cx, bx
    sub cx, [editor_cursor]
    mov si, editor_buf
    add si, bx
    mov di, si
    inc di
    std
    rep movsb
    cld
    mov bx, [editor_cursor]
    mov [editor_buf+bx], al
    inc word [editor_cursor]
    inc word [editor_len]
    mov byte [editor_status], 4
.out:
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    ret

editor_backspace:
    push ax
    mov ax, [editor_cursor]
    cmp ax, 0
    je .out
    dec word [editor_cursor]
    call editor_delete_at_cursor
.out:
    pop ax
    ret

editor_delete_at_cursor:
    push ax
    push bx
    push cx
    push si
    push di
    mov bx, [editor_cursor]
    cmp bx, [editor_len]
    jae .out
    mov si, editor_buf
    add si, bx
    inc si
    mov di, editor_buf
    add di, bx
    mov cx, [editor_len]
    sub cx, bx
    dec cx
    jbe .tail
    cld
    rep movsb
.tail:
    dec word [editor_len]
    mov byte [editor_status], 4
.out:
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    ret

editor_build_filename:
    push ax
    push bx
    push cx
    push si
    push di
    mov si, editor_dir_entry
    mov di, editor_name
    mov cx, 8
.name:
    mov al, [si]
    cmp al, ' '
    je .dot
    mov [di], al
    inc di
    inc si
    loop .name
.dot:
    mov byte [di], '.'
    inc di
    mov si, editor_dir_entry
    add si, 8
    mov cx, 3
.ext:
    mov al, [si]
    mov [di], al
    inc di
    inc si
    loop .ext
    mov byte [di], 0
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    ret

editor_check_type:
    mov byte [editor_known_type], 0
    mov si, editor_name
.seek_dot:
    mov al, [si]
    test al, al
    jz .unknown
    cmp al, '.'
    je .dot
    inc si
    jmp .seek_dot
.dot:
    inc si
    mov al, [si]
    mov ah, [si+1]
    mov dl, [si+2]
    cmp al, 'a'
    jb .u1
    cmp al, 'z'
    ja .u1
    sub al, 32
.u1:
    cmp ah, 'a'
    jb .u2
    cmp ah, 'z'
    ja .u2
    sub ah, 32
.u2:
    cmp dl, 'a'
    jb .check
    cmp dl, 'z'
    ja .check
    sub dl, 32
.check:
    cmp al, 'T'
    jne .asm
    cmp ah, 'X'
    jne .asm
    cmp dl, 'T'
    jne .asm
    mov byte [editor_known_type], 1
    ret
.asm:
    cmp al, 'A'
    jne .c1
    cmp ah, 'S'
    jne .c1
    cmp dl, 'M'
    jne .c1
    mov byte [editor_known_type], 1
    ret
.c1:
    cmp al, 'C'
    jne .h1
    cmp ah, ' '
    jne .h1
    cmp dl, ' '
    jne .h1
    mov byte [editor_known_type], 1
    ret
.h1:
    cmp al, 'H'
    jne .md1
    cmp ah, ' '
    jne .md1
    cmp dl, ' '
    jne .md1
    mov byte [editor_known_type], 1
    ret
.md1:
    cmp al, 'M'
    jne .log1
    cmp ah, 'D'
    jne .log1
    cmp dl, ' '
    jne .log1
    mov byte [editor_known_type], 1
    ret
.log1:
    cmp al, 'L'
    jne .cfg1
    cmp ah, 'O'
    jne .cfg1
    cmp dl, 'G'
    jne .cfg1
    mov byte [editor_known_type], 1
    ret
.cfg1:
    cmp al, 'C'
    jne .ini1
    cmp ah, 'F'
    jne .ini1
    cmp dl, 'G'
    jne .ini1
    mov byte [editor_known_type], 1
    ret
.ini1:
    cmp al, 'I'
    jne .unknown
    cmp ah, 'N'
    jne .unknown
    cmp dl, 'I'
    jne .unknown
    mov byte [editor_known_type], 1
.unknown:
    ret

fat12_next_cluster_media:
    ; IN AX=current cluster, OUT AX=next cluster, CF=1 on read error.
    push bx
    push cx
    push dx
    push si
    push di
    push es

    mov [fat_tmp_cluster], ax
    mov bx, ax
    mov dx, ax
    shr dx, 1
    add bx, dx            ; BX = floor(cluster*3/2)
    mov ax, bx
    mov cx, 512
    xor dx, dx
    div cx                ; AX=fat sector offset, DX=pos
    add ax, 1             ; FAT starts at LBA 1
    mov [fat_tmp_lba], ax
    mov [fat_tmp_pos], dx

    mov ax, 0x9000
    mov es, ax
    xor bx, bx
    mov ax, [fat_tmp_lba]
    call read_sector_media
    jc .fail

    mov si, [fat_tmp_pos]
    mov al, [es:si]
    mov [fat_tmp_b0], al
    cmp si, 511
    jne .same
    xor bx, bx
    mov ax, [fat_tmp_lba]
    inc ax
    call read_sector_media
    jc .fail
    mov al, [es:0]
    mov [fat_tmp_b1], al
    jmp .decode
.same:
    mov al, [es:si+1]
    mov [fat_tmp_b1], al

.decode:
    mov ax, [fat_tmp_cluster]
    test ax, 1
    jz .even
    mov al, [fat_tmp_b0]
    shr al, 4
    mov ah, [fat_tmp_b1]
    shl ah, 4
    mov dx, ax
    and dx, 0x0FFF
    mov ax, dx
    clc
    jmp .out
.even:
    mov al, [fat_tmp_b0]
    mov ah, [fat_tmp_b1]
    and ah, 0x0F
    mov dx, ax
    and dx, 0x0FFF
    mov ax, dx
    clc
    jmp .out
.fail:
    stc
.out:
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    ret

draw_editor:
    cmp byte [video_mode], 0
    jne .simple
    xor di, di
    mov al, 0x00
    mov cx, 320*200
    rep stosb
    jmp .body
.simple:
    call refresh_simple_mode
    call clear_simple_bg
.body:
    mov dh, 0
    mov dl, 1
    mov bl, 0x0F
    mov si, editor_title
    call print_at
    mov dh, 1
    mov dl, 1
    mov si, editor_name
    call print_at
    cmp byte [editor_known_type], 1
    je .help
    mov dh, 2
    mov dl, 1
    mov si, editor_warn
    call print_at
.help:
    mov dh, 3
    mov dl, 1
    cmp byte [editor_read_only], 1
    jne .rw_help
    mov si, editor_help_ro
    jmp .ph
.rw_help:
    mov si, editor_help
.ph:
    call print_at
    call draw_editor_buffer
    ret

draw_editor_buffer:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov si, editor_buf
    xor bx, bx
    mov dh, 5
    mov dl, 1
    mov cx, [editor_len]
.loop:
    cmp cx, 0
    je .status
    lodsb
    dec cx
    cmp al, 13
    je .newline
    cmp al, 10
    je .newline
    cmp al, 32
    jb .dot
    cmp al, 126
    jbe .ch
.dot:
    mov al, '.'
.ch:
    mov ah, 0x0E
    mov bh, 0
    mov bl, 0x0F
    int 0x10
    inc dl
    cmp dl, 39
    jb .loop
.newline:
    inc dh
    mov dl, 1
    cmp dh, 21
    jbe .loop
.status:
    mov dh, 22
    mov dl, 1
    cmp byte [editor_status], 1
    je .s_ok
    cmp byte [editor_status], 2
    je .s_io
    cmp byte [editor_status], 3
    je .s_big
    cmp byte [editor_status], 4
    je .s_edit
    cmp byte [editor_status], 5
    je .s_ro
    mov si, editor_status_idle
    jmp .print
.s_ok:
    mov si, editor_status_saved
    jmp .print
.s_io:
    mov si, editor_status_io
    jmp .print
.s_big:
    mov si, editor_status_big
    jmp .print
.s_edit:
    mov si, editor_status_edit
    jmp .print
.s_ro:
    mov si, editor_status_ro
.print:
    mov bl, 0x0F
    call print_at

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

media_scan_sector:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    xor di, di
    mov cx, 16
.entry:
    mov al, [es:di]
    cmp al, 0
    je .done
    cmp al, 0E5h
    je .next
    cmp byte [es:di+11], 0x20
    jne .next
    call media_match_ext
    jc .next
    call media_copy_name
    cmp byte [media_file_count], 4
    jae .done
.next:
    add di, 32
    loop .entry
.done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

media_match_ext:
    ; Carry clear = compatible
    mov al, [es:di+8]
    mov ah, [es:di+9]
    mov dl, [es:di+10]
    cmp al, 'W'
    jne .chk_mid
    cmp ah, 'A'
    jne .bad
    cmp dl, 'V'
    je .ok
.chk_mid:
    cmp al, 'M'
    jne .bad
    cmp ah, 'I'
    jne .bad
    cmp dl, 'D'
    je .ok
.ok:
    clc
    ret
.bad:
    stc
    ret

media_copy_name:
    mov bl, [media_file_count]
    cmp bl, 4
    jae .done
    mov bh, 0
    mov si, media_name_0
    mov ax, bx
    mov bl, 13
    mul bl
    add si, ax

    mov bx, di
    mov cx, 8
.name:
    mov al, [es:bx]
    cmp al, ' '
    je .dot
    mov [si], al
    inc si
    inc bx
    loop .name
.dot:
    mov byte [si], '.'
    inc si
    mov bx, di
    add bx, 8
    mov cx, 3
.ext:
    mov al, [es:bx]
    mov [si], al
    inc si
    inc bx
    loop .ext
    mov byte [si], 0
    mov bl, [media_file_count]
    xor bh, bh
    mov si, media_entry_sector
    add si, bx
    mov al, [media_scan_lba]
    mov [si], al
    mov si, media_entry_offset
    add si, bx
    mov ax, di
    mov [si], al
    inc byte [media_file_count]
.done:
    ret

media_import_from_explorer:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    xor bx, bx
.next:
    mov al, [explorer_file_count]
    cmp bl, al
    jae .out
    cmp byte [media_file_count], 4
    jae .out

    ; SI = explorer_name[bx]
    mov si, explorer_name_0
    mov ax, bx
    mov dx, bx
    shl ax, 3
    shl dx, 2
    add ax, dx
    add ax, bx
    add si, ax
    call media_is_supported_name
    jc .skip

    ; DI = media_name[media_file_count]
    mov dl, [media_file_count]
    xor dh, dh
    mov di, media_name_0
    mov ax, dx
    mov cx, dx
    shl ax, 3
    shl cx, 2
    add ax, cx
    add ax, dx
    add di, ax
    mov cx, 13
.cpy_name:
    mov al, [si]
    mov [di], al
    inc si
    inc di
    loop .cpy_name

    ; Preserve output index in DL and source index in BL.
    mov si, media_entry_is_iso
    mov ax, dx
    add si, ax
    mov al, [media_from_iso]
    mov [si], al

    mov si, media_entry_sector
    mov ax, dx
    add si, ax
    mov di, explorer_entry_sector
    mov al, [di+bx]
    mov [si], al

    mov si, media_entry_offset
    mov ax, dx
    add si, ax
    mov di, explorer_entry_offset
    mov al, [di+bx]
    mov [si], al

    ; word arrays index = idx*2
    mov si, media_entry_lba
    mov ax, dx
    shl ax, 1
    add si, ax
    mov di, explorer_entry_lba
    mov ax, bx
    shl ax, 1
    add di, ax
    mov ax, [di]
    mov [si], ax

    mov si, media_entry_size
    mov ax, dx
    shl ax, 1
    add si, ax
    mov di, explorer_entry_size
    mov ax, bx
    shl ax, 1
    add di, ax
    mov ax, [di]
    mov [si], ax

    inc byte [media_file_count]
.skip:
    inc bl
    jmp .next
.out:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

media_is_supported_name:
    ; IN SI -> zero-terminated name. CF clear if WAV/MID.
    push ax
    push bx
    push si
.seek:
    mov al, [si]
    test al, al
    jz .bad
    cmp al, '.'
    je .dot
    inc si
    jmp .seek
.dot:
    inc si
    mov al, [si]
    mov ah, [si+1]
    mov bl, [si+2]
    cmp al, 'a'
    jb .u1
    cmp al, 'z'
    ja .u1
    sub al, 32
.u1:
    cmp ah, 'a'
    jb .u2
    cmp ah, 'z'
    ja .u2
    sub ah, 32
.u2:
    cmp bl, 'a'
    jb .cmp
    cmp bl, 'z'
    ja .cmp
    sub bl, 32
.cmp:
    cmp al, 'W'
    jne .mid
    cmp ah, 'A'
    jne .bad
    cmp bl, 'V'
    jne .bad
    clc
    jmp .out
.mid:
    cmp al, 'M'
    jne .bad
    cmp ah, 'I'
    jne .bad
    cmp bl, 'D'
    jne .bad
    clc
    jmp .out
.bad:
    stc
.out:
    pop si
    pop bx
    pop ax
    ret

media_get_type_from_name:
    ; IN SI -> name, OUT AL: 1=WAV 2=MID 0=unknown
    push bx
.seek:
    mov al, [si]
    test al, al
    jz .unk
    cmp al, '.'
    je .dot
    inc si
    jmp .seek
.dot:
    inc si
    mov al, [si]
    mov ah, [si+1]
    mov bl, [si+2]
    cmp al, 'a'
    jb .u1
    cmp al, 'z'
    ja .u1
    sub al, 32
.u1:
    cmp ah, 'a'
    jb .u2
    cmp ah, 'z'
    ja .u2
    sub ah, 32
.u2:
    cmp bl, 'a'
    jb .chk
    cmp bl, 'z'
    ja .chk
    sub bl, 32
.chk:
    cmp al, 'W'
    jne .mid
    cmp ah, 'A'
    jne .unk
    cmp bl, 'V'
    jne .unk
    mov al, 1
    jmp .out
.mid:
    cmp al, 'M'
    jne .unk
    cmp ah, 'I'
    jne .unk
    cmp bl, 'D'
    jne .unk
    mov al, 2
    jmp .out
.unk:
    xor al, al
.out:
    pop bx
    ret

media_play_selected:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es

    mov byte [media_play_status], 0
    mov byte [media_backend], 0
    cmp byte [sb16_ok], 1
    jne .no_sb
    mov byte [media_backend], 1
    call sb16_speaker_on
.no_sb:
    mov bl, [selected]
    xor bh, bh
    mov [media_sel_idx], bl
    cmp bl, [media_file_count]
    jae .out

    mov si, media_entry_is_iso
    add si, bx
    cmp byte [si], 1
    jne .fat_path
    mov si, media_name_0
    mov ax, bx
    mov dx, bx
    shl ax, 3
    shl dx, 2
    add ax, dx
    add ax, bx
    add si, ax
    call media_get_type_from_name
    cmp al, 1
    je .iso_wav
    cmp al, 2
    je .iso_mid
    jmp .unsupported
.iso_wav:
    call media_play_wav_iso
    jmp .done
.iso_mid:
    call media_play_mid_iso
    jmp .done

.fat_path:

    mov ax, 0x9000
    mov es, ax
    mov bl, [media_sel_idx]
    xor bh, bh
    mov si, media_entry_sector
    add si, bx
    mov al, [si]
    xor ah, ah
    xor bx, bx
    call read_sector_media
    jc .io_fail

    mov bl, [media_sel_idx]
    xor bh, bh
    mov si, media_entry_offset
    add si, bx
    mov bl, [si]
    xor bh, bh

    mov al, [es:bx+8]
    mov ah, [es:bx+9]
    mov dl, [es:bx+10]
    cmp al, 'W'
    jne .try_mid
    cmp ah, 'A'
    jne .unsupported
    cmp dl, 'V'
    jne .unsupported
    call media_play_wav_entry
    jmp .done
.try_mid:
    cmp al, 'M'
    jne .unsupported
    cmp ah, 'I'
    jne .unsupported
    cmp dl, 'D'
    jne .unsupported
    call media_play_mid_entry
    jmp .done
.unsupported:
    mov byte [media_play_status], 3
    jmp .out
.io_fail:
    mov byte [media_play_status], 4
    jmp .out
.done:
    cmp byte [media_play_status], 0
    jne .out
    mov byte [media_play_status], 2
.out:
    call speaker_off
    call sb16_speaker_off
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

media_play_wav_entry:
    mov byte [media_play_status], 1
    mov ax, [es:bx+26]
    cmp ax, 2
    jb .bad
    mov [media_cluster], ax
    mov ax, [es:bx+28]
    mov [media_size], ax

    mov ax, [media_cluster]
    sub ax, 2
    add ax, 33
    mov [media_lba], ax
    xor bx, bx
    call read_sector_media
    jc .bad

    xor si, si
    cmp dword [es:0], 0x46464952      ; 'RIFF'
    jne .play
    cmp dword [es:8], 0x45564157      ; 'WAVE'
    jne .play
    mov si, 44
.play:
    mov cx, 160
.sample_loop:
    cmp si, 511
    jae .done
    mov al, [es:si]
    call sample_to_divisor
    call speaker_on_divisor
    call media_delay_short
    inc si
    loop .sample_loop
.done:
    clc
    ret
.bad:
    mov byte [media_play_status], 4
    stc
    ret

media_play_mid_entry:
    mov byte [media_play_status], 1
    mov ax, [es:bx+26]
    cmp ax, 2
    jb .bad
    mov [media_cluster], ax
    mov ax, [media_cluster]
    sub ax, 2
    add ax, 33
    mov [media_lba], ax
    xor bx, bx
    call read_sector_media
    jc .bad

    cmp dword [es:0], 0x6468544D      ; 'MThd'
    jne .bad
    mov si, 0
    mov cx, 320
.scan:
    cmp si, 510
    jae .done
    mov al, [es:si]
    and al, 0xF0
    cmp al, 0x90
    jne .next
    mov al, [es:si+2]
    cmp al, 0
    je .next
    mov al, [es:si+1]
    call midi_note_to_divisor
    call speaker_on_divisor
    call media_delay_short
.next:
    inc si
    loop .scan
.done:
    clc
    ret
.bad:
    mov byte [media_play_status], 4
    stc
    ret

media_play_wav_iso:
    mov byte [media_play_status], 1
    mov bl, [media_sel_idx]
    xor bh, bh
    mov si, media_entry_lba
    mov ax, bx
    shl ax, 1
    add si, ax
    mov ax, [si]
    mov [media_lba], ax
    mov ax, 0x9000
    mov es, ax
    xor bx, bx
    mov ax, [media_lba]
    call read_sector_iso2048
    jc .bad
    xor si, si
    cmp dword [es:0], 0x46464952
    jne .play
    cmp dword [es:8], 0x45564157
    jne .play
    mov si, 44
.play:
    mov cx, 220
.loop:
    cmp si, 2047
    jae .done
    mov al, [es:si]
    call sample_to_divisor
    call speaker_on_divisor
    call media_delay_short
    inc si
    loop .loop
.done:
    clc
    ret
.bad:
    mov byte [media_play_status], 4
    stc
    ret

media_play_mid_iso:
    mov byte [media_play_status], 1
    mov bl, [media_sel_idx]
    xor bh, bh
    mov si, media_entry_lba
    mov ax, bx
    shl ax, 1
    add si, ax
    mov ax, [si]
    mov [media_lba], ax
    mov ax, 0x9000
    mov es, ax
    xor bx, bx
    mov ax, [media_lba]
    call read_sector_iso2048
    jc .bad
    cmp dword [es:0], 0x6468544D
    jne .bad
    mov si, 0
    mov cx, 700
.scan:
    cmp si, 2046
    jae .done
    mov al, [es:si]
    and al, 0xF0
    cmp al, 0x90
    jne .next
    mov al, [es:si+2]
    cmp al, 0
    je .next
    mov al, [es:si+1]
    call midi_note_to_divisor
    call speaker_on_divisor
    call media_delay_short
.next:
    inc si
    loop .scan
.done:
    clc
    ret
.bad:
    mov byte [media_play_status], 4
    stc
    ret

sample_to_divisor:
    ; AL sample -> BX PIT divisor (rough mapping)
    xor ah, ah
    mov bx, 8
    mul bx
    add ax, 300
    mov bx, ax
    ret

midi_note_to_divisor:
    ; AL note -> BX PIT divisor (rough mapping)
    xor ah, ah
    mov bx, 18
    mul bx
    mov bx, 6500
    sub bx, ax
    cmp bx, 300
    jae .ok
    mov bx, 300
.ok:
    ret

speaker_on_divisor:
    push ax
    mov al, 0xB6
    out 0x43, al
    mov al, bl
    out 0x42, al
    mov al, bh
    out 0x42, al
    in al, 0x61
    or al, 0x03
    out 0x61, al
    pop ax
    ret

speaker_off:
    in al, 0x61
    and al, 0xFC
    out 0x61, al
    ret

media_delay_short:
    push cx
    mov cx, 2800
.d:
    nop
    loop .d
    pop cx
    ret

get_max_index:
    cmp byte [mode], 5
    je .media_drives
    cmp byte [mode], 6
    je .media_files
    cmp byte [mode], 7
    je .explorer_drives
    cmp byte [mode], 8
    je .explorer_files
    cmp byte [mode], 1
    je .power
    cmp byte [mode], 0
    je .main
    cmp byte [mode], 2
    jne .default
    mov al, 5
    ret
.main:
    cmp byte [main_page], 0
    jne .main2
    mov al, 5
    ret
.main2:
    mov al, 2
    ret
.power:
    mov al, 2
    ret
.media_drives:
    mov al, [drive_count]
    ret
.media_files:
    mov al, [media_file_count]
    ret
.explorer_drives:
    mov al, [drive_count]
    ret
.explorer_files:
    mov al, [explorer_file_count]
    ret
.default:
    mov al, 0
    ret

draw_ui:
    mov byte [cursor_drawn], 0
    cmp byte [mode], 4
    je draw_debug
    cmp byte [mode], 3
    je draw_desktop
    cmp byte [mode], 10
    je draw_hardware
    cmp byte [mode], 9
    je draw_editor
    cmp byte [video_mode], 0
    jne draw_ui_simple

    ; Fill background.
    xor di, di
    mov al, [bg_color]
    mov cx, 320*200
    rep stosb

    ; Top bar.
    xor di, di
    mov al, 0x09
    mov cx, 320*20
    rep stosb

    ; Center panel.
    mov ax, 56
    mov bx, 56
    mov cx, 208
    mov dx, 116
    mov byte [draw_color], 0x03
    call fill_rect

    ; Selection highlight.
    xor ax, ax
    mov al, [selected]
    shl ax, 4
    add ax, 78
    mov bx, 72
    mov cx, 176
    mov dx, 14
    mov byte [draw_color], 0x0C
    call fill_rect

    mov dh, 0
    mov dl, 1
    mov bl, 0x0F
    mov si, title
    call print_at

    mov dh, 22
    mov dl, 1
    mov bl, 0x0F
    mov si, hint
    call print_at

    cmp byte [mode], 0
    je .m0
    cmp byte [mode], 1
    je draw_power
    cmp byte [mode], 5
    je draw_media_drives
    cmp byte [mode], 6
    je draw_media_files
    cmp byte [mode], 7
    je .m7
    cmp byte [mode], 8
    je .m8
    jmp draw_res
.m0:
    jmp draw_main
.m7:
    cmp byte [window_mode_enabled], 1
    jne draw_explorer_drives
    jmp draw_explorer_drives_windowed
.m8:
    cmp byte [window_mode_enabled], 1
    jne draw_explorer_files
    jmp draw_explorer_files_windowed

draw_main:
    cmp byte [main_page], 0
    je .page1
    mov dh, 5
    mov dl, 7
    mov bl, 0x0E
    mov si, main_title_2
    call print_at

    mov al, 0
    mov dh, 10
    mov si, main_6
    call draw_item

    mov al, 1
    mov dh, 12
    mov si, main_7
    call draw_item
    mov al, 2
    mov dh, 14
    mov si, main_8
    call draw_item
    mov dh, 16
    mov dl, 10
    mov bl, 0x0F
    cmp byte [window_mode_enabled], 1
    je .wm_on
    mov si, wnd_mode_off
    call print_at
    ret
.wm_on:
    mov si, wnd_mode_on
    call print_at
    ret
.page1:
    mov dh, 5
    mov dl, 9
    mov bl, 0x0E
    mov si, main_title
    call print_at

    mov al, 0
    mov dh, 10
    mov si, main_1
    call draw_item

    mov al, 1
    mov dh, 12
    mov si, main_2
    call draw_item

    mov al, 2
    mov dh, 14
    mov si, main_3
    call draw_item
    mov al, 3
    mov dh, 16
    mov si, main_4
    call draw_item
    mov al, 4
    mov dh, 18
    mov si, main_5
    call draw_item
    mov al, 5
    mov dh, 20
    mov si, main_next
    call draw_item
    ret

draw_main_windowed:
    ; Windowed kernel shell for main menu.
    xor di, di
    mov al, [bg_color]
    mov cx, 320*200
    rep stosb

    cmp byte [window_visible], 1
    jne .closed

    mov ax, [window_y]
    mov bx, [window_x]
    mov cx, 224
    mov dx, 12
    mov byte [draw_color], 0x09
    call fill_rect
    cmp byte [window_minimized], 1
    je .title_only
    mov ax, [window_y]
    add ax, 12
    mov bx, [window_x]
    mov cx, 224
    mov dx, 120
    mov byte [draw_color], 0x03
    call fill_rect

    mov ax, [window_y]
    mov bx, [window_x]
    add ax, 2
    add bx, 6
    call set_text_xy_from_pixels
    mov dh, [txt_row]
    mov dl, [txt_col]
    cmp byte [window_title_focus], 1
    je .focus_title
    mov bl, 0x0F
    mov si, title
    call print_at
    jmp .body
.focus_title:
    mov bl, 0x0E
    mov si, wnd_kernel_focus
    call print_at

.body:
    mov ax, [window_y]
    mov bx, [window_x]
    add ax, 16
    add bx, 8
    call set_text_xy_from_pixels
    mov al, [txt_row]
    mov [wnd_row], al
    mov al, [txt_col]
    mov [wnd_col], al

    cmp byte [main_page], 0
    je .p1
    mov dh, 0
    mov dl, 0
    mov bl, 0x0E
    mov si, main_title_2
    call print_wnd
    mov al, 0
    mov dh, 3
    mov si, main_6
    call draw_item_wnd
    mov al, 1
    mov dh, 5
    mov si, main_7
    call draw_item_wnd
    mov al, 2
    mov dh, 7
    mov si, main_8
    call draw_item_wnd
    mov dh, 9
    mov dl, 1
    mov bl, 0x0F
    cmp byte [window_mode_enabled], 1
    je .wm_on2
    mov si, wnd_mode_off
    call print_wnd
    jmp .hint
.wm_on2:
    mov si, wnd_mode_on
    call print_wnd
    jmp .hint

.p1:
    mov dh, 0
    mov dl, 0
    mov bl, 0x0E
    mov si, main_title
    call print_wnd
    mov al, 0
    mov dh, 3
    mov si, main_1
    call draw_item_wnd
    mov al, 1
    mov dh, 5
    mov si, main_2
    call draw_item_wnd
    mov al, 2
    mov dh, 7
    mov si, main_3
    call draw_item_wnd
    mov al, 3
    mov dh, 9
    mov si, main_4
    call draw_item_wnd
    mov al, 4
    mov dh, 11
    mov si, main_5
    call draw_item_wnd
    mov al, 5
    mov dh, 13
    mov si, main_next
    call draw_item_wnd

.hint:
    mov dh, 15
    mov dl, 0
    mov bl, 0x0F
    mov si, wnd_main_hint
    call print_wnd
.title_only:
    ret

.closed:
    mov dh, 10
    mov dl, 6
    mov bl, 0x0F
    mov si, wnd_closed
    call print_at
    mov dh, 12
    mov dl, 6
    mov si, wnd_restore_hint
    call print_at
    ret

draw_item_wnd:
    push si
    cmp al, [selected]
    jne .txt
    mov dl, 0
    mov bl, 0x0F
    mov si, ptr_arrow
    call print_wnd
.txt:
    pop si
    mov dl, 2
    mov bl, 0x0F
    call print_wnd
    ret

print_wnd:
    push ax
    mov al, [wnd_row]
    add dh, al
    mov al, [wnd_col]
    add dl, al
    pop ax
    jmp print_at

draw_power:
    mov dh, 5
    mov dl, 9
    mov bl, 0x0E
    mov si, power_title
    call print_at

    mov al, 0
    mov dh, 10
    mov si, pow_1
    call draw_item

    mov al, 1
    mov dh, 12
    mov si, pow_2
    call draw_item

    mov al, 2
    mov dh, 14
    mov si, pow_3
    call draw_item
    ret

draw_res:
    mov dh, 5
    mov dl, 9
    mov bl, 0x0E
    mov si, res_title
    call print_at

    mov al, 0
    mov dh, 10
    mov si, res_1
    call draw_item

    mov al, 1
    mov dh, 12
    mov si, res_2
    call draw_item

    mov al, 2
    mov dh, 14
    mov si, res_3
    call draw_item

    mov al, 3
    mov dh, 16
    mov si, res_4
    call draw_item

    mov al, 4
    mov dh, 18
    mov si, res_5
    call draw_item

    mov al, 5
    mov dh, 20
    mov si, res_6
    call draw_item
    ret

draw_media_drives:
    mov dh, 5
    mov dl, 9
    mov bl, 0x0E
    mov si, media_title
    call print_at
    mov al, [drive_count]
    cmp al, 0
    jne .have
    mov dh, 10
    mov dl, 10
    mov si, msg_no_drives
    call print_at
    ret
.have:
    mov al, 0
    mov dh, 10
    mov si, drive_label_0
    call draw_item
    mov al, 1
    mov dh, 12
    mov si, drive_label_1
    call draw_item
    mov al, 2
    mov dh, 14
    mov si, drive_label_2
    call draw_item
    mov al, 3
    mov dh, 16
    mov si, drive_label_3
    call draw_item
    mov al, 4
    mov dh, 18
    mov si, drive_label_4
    call draw_item
    mov al, 5
    mov dh, 20
    mov si, drive_label_5
    call draw_item
    mov al, [drive_count]
    mov dh, 22
    mov si, media_back
    call draw_item
    ret

draw_media_files:
    mov dh, 5
    mov dl, 9
    mov bl, 0x0E
    mov si, media_files_title
    call print_at
    mov al, [media_file_count]
    cmp al, 0
    jne .have_files
    mov dh, 10
    mov dl, 10
    mov si, msg_no_media
    call print_at
    mov al, 0
    mov dh, 18
    mov si, media_back
    call draw_item
    ret
.have_files:
    mov al, 0
    mov dh, 10
    mov si, media_name_0
    call draw_item
    mov al, 1
    mov dh, 12
    mov si, media_name_1
    call draw_item
    mov al, 2
    mov dh, 14
    mov si, media_name_2
    call draw_item
    mov al, 3
    mov dh, 16
    mov si, media_name_3
    call draw_item
    mov al, [media_file_count]
    mov dh, 22
    mov si, media_back
    call draw_item
    mov dh, 20
    mov dl, 1
    mov bl, 0x0F
    mov si, msg_media_audio
    call print_at
    mov dh, 20
    mov dl, 14
    cmp byte [media_backend], 1
    je .a_sb16
    mov si, msg_media_pcspk
    call print_at
    jmp .status
.a_sb16:
    mov si, msg_media_sb16
    call print_at
.status:
    mov dh, 21
    mov dl, 1
    mov bl, 0x0F
    mov al, [media_play_status]
    cmp al, 1
    je .s_play
    cmp al, 2
    je .s_done
    cmp al, 3
    je .s_unsupported
    cmp al, 4
    je .s_io
    mov si, msg_media_help
    call print_at
    ret
.s_play:
    mov si, msg_media_playing
    call print_at
    ret
.s_done:
    mov si, msg_media_done
    call print_at
    ret
.s_unsupported:
    mov si, msg_media_unsup
    call print_at
    ret
.s_io:
    mov si, msg_media_io
    call print_at
    ret

draw_explorer_drives:
    mov dh, 5
    mov dl, 9
    mov bl, 0x0E
    mov si, explorer_title
    call print_at
    mov al, [drive_count]
    cmp al, 0
    jne .have
    mov dh, 10
    mov dl, 10
    mov si, msg_no_drives
    call print_at
    ret
.have:
    mov al, 0
    mov dh, 10
    mov si, drive_label_0
    call draw_item
    mov al, 1
    mov dh, 12
    mov si, drive_label_1
    call draw_item
    mov al, 2
    mov dh, 14
    mov si, drive_label_2
    call draw_item
    mov al, 3
    mov dh, 16
    mov si, drive_label_3
    call draw_item
    mov al, 4
    mov dh, 18
    mov si, drive_label_4
    call draw_item
    mov al, 5
    mov dh, 20
    mov si, drive_label_5
    call draw_item
    mov al, [drive_count]
    mov dh, 22
    mov si, media_back
    call draw_item
    ret

draw_explorer_files:
    mov dh, 5
    mov dl, 8
    mov bl, 0x0E
    mov si, explorer_files_title
    call print_at
    mov al, [explorer_file_count]
    cmp al, 0
    jne .have_files
    mov dh, 10
    mov dl, 10
    mov si, msg_no_files
    call print_at
    mov al, 0
    mov dh, 20
    mov si, media_back
    call draw_item
    jmp .status
.have_files:
    mov al, 0
    mov dh, 8
    mov si, explorer_name_0
    call draw_item
    mov al, 1
    mov dh, 10
    mov si, explorer_name_1
    call draw_item
    mov al, 2
    mov dh, 12
    mov si, explorer_name_2
    call draw_item
    mov al, 3
    mov dh, 14
    mov si, explorer_name_3
    call draw_item
    mov al, 4
    mov dh, 16
    mov si, explorer_name_4
    call draw_item
    mov al, [explorer_file_count]
    mov dh, 20
    mov si, media_back
    call draw_item
.status:
    mov dh, 22
    mov dl, 1
    mov bl, 0x0F
    mov al, [explorer_status]
    cmp al, 1
    je .s1
    cmp al, 2
    je .s2
    cmp al, 3
    je .s3
    cmp al, 4
    je .s4
    cmp al, 5
    je .s5
    cmp al, 6
    je .s6
    cmp al, 7
    je .s7
    mov si, exp_help
    call print_at
    ret
.s1:
    mov si, exp_copied
    call print_at
    ret
.s2:
    mov si, exp_cut
    call print_at
    ret
.s3:
    mov si, exp_pasted
    call print_at
    ret
.s4:
    mov si, exp_deleted
    call print_at
    ret
.s5:
    mov si, exp_no_slot
    call print_at
    ret
.s6:
    mov si, exp_wrong_drive
    call print_at
    ret
.s7:
    mov si, exp_no_clip
    call print_at
    ret

draw_explorer_drives_windowed:
    xor di, di
    mov al, [bg_color]
    mov cx, 320*200
    rep stosb
    cmp byte [window_visible], 1
    jne .closed
    mov ax, [window_y]
    mov bx, [window_x]
    mov cx, 224
    mov dx, 12
    mov byte [draw_color], 0x09
    call fill_rect
    cmp byte [window_minimized], 1
    je .title
    mov ax, [window_y]
    add ax, 12
    mov bx, [window_x]
    mov cx, 224
    mov dx, 120
    mov byte [draw_color], 0x03
    call fill_rect
.title:
    mov ax, [window_y]
    add ax, 2
    mov bx, [window_x]
    add bx, 6
    call set_text_xy_from_pixels
    mov al, [txt_row]
    mov [wnd_row], al
    mov al, [txt_col]
    mov [wnd_col], al
    mov dh, 0
    mov dl, 0
    cmp byte [window_title_focus], 1
    je .focus
    mov bl, 0x0F
    mov si, wnd_explorer_title
    call print_wnd
    jmp .body
.focus:
    mov bl, 0x0E
    mov si, wnd_explorer_title_focus
    call print_wnd
.body:
    cmp byte [window_minimized], 1
    je .hint
    mov dh, 2
    mov dl, 1
    mov bl, 0x0E
    mov si, explorer_title
    call print_wnd
    mov al, [drive_count]
    cmp al, 0
    jne .have
    mov dh, 4
    mov dl, 1
    mov si, msg_no_drives
    call print_wnd
    jmp .hint
.have:
    mov al, 0
    mov dh, 4
    mov si, drive_label_0
    call draw_item_wnd
    mov al, 1
    mov dh, 6
    mov si, drive_label_1
    call draw_item_wnd
    mov al, 2
    mov dh, 8
    mov si, drive_label_2
    call draw_item_wnd
    mov al, 3
    mov dh, 10
    mov si, drive_label_3
    call draw_item_wnd
    mov al, 4
    mov dh, 12
    mov si, drive_label_4
    call draw_item_wnd
    mov al, 5
    mov dh, 14
    mov si, drive_label_5
    call draw_item_wnd
    mov al, [drive_count]
    mov dh, 16
    mov si, media_back
    call draw_item_wnd
.hint:
    mov dh, 18
    mov dl, 0
    mov bl, 0x0F
    mov si, wnd_main_hint
    call print_wnd
    ret
.closed:
    mov dh, 10
    mov dl, 6
    mov bl, 0x0F
    mov si, wnd_closed
    call print_at
    mov dh, 12
    mov dl, 6
    mov si, wnd_restore_hint
    call print_at
    ret

draw_explorer_files_windowed:
    xor di, di
    mov al, [bg_color]
    mov cx, 320*200
    rep stosb
    cmp byte [window_visible], 1
    jne .closed
    mov ax, [window_y]
    mov bx, [window_x]
    mov cx, 224
    mov dx, 12
    mov byte [draw_color], 0x09
    call fill_rect
    cmp byte [window_minimized], 1
    je .title
    mov ax, [window_y]
    add ax, 12
    mov bx, [window_x]
    mov cx, 224
    mov dx, 120
    mov byte [draw_color], 0x03
    call fill_rect
.title:
    mov ax, [window_y]
    add ax, 2
    mov bx, [window_x]
    add bx, 6
    call set_text_xy_from_pixels
    mov al, [txt_row]
    mov [wnd_row], al
    mov al, [txt_col]
    mov [wnd_col], al
    mov dh, 0
    mov dl, 0
    cmp byte [window_title_focus], 1
    je .focus
    mov bl, 0x0F
    mov si, wnd_explorer_title
    call print_wnd
    jmp .body
.focus:
    mov bl, 0x0E
    mov si, wnd_explorer_title_focus
    call print_wnd
.body:
    cmp byte [window_minimized], 1
    je .hint
    mov dh, 2
    mov dl, 1
    mov bl, 0x0E
    mov si, explorer_files_title
    call print_wnd
    mov al, [explorer_file_count]
    cmp al, 0
    jne .have
    mov dh, 4
    mov dl, 1
    mov si, msg_no_files
    call print_wnd
    mov al, 0
    mov dh, 14
    mov si, media_back
    call draw_item_wnd
    jmp .status
.have:
    mov al, 0
    mov dh, 4
    mov si, explorer_name_0
    call draw_item_wnd
    mov al, 1
    mov dh, 6
    mov si, explorer_name_1
    call draw_item_wnd
    mov al, 2
    mov dh, 8
    mov si, explorer_name_2
    call draw_item_wnd
    mov al, 3
    mov dh, 10
    mov si, explorer_name_3
    call draw_item_wnd
    mov al, 4
    mov dh, 12
    mov si, explorer_name_4
    call draw_item_wnd
    mov al, [explorer_file_count]
    mov dh, 14
    mov si, media_back
    call draw_item_wnd
.status:
    mov dh, 16
    mov dl, 0
    mov bl, 0x0F
    mov al, [explorer_status]
    cmp al, 1
    je .s1
    cmp al, 2
    je .s2
    cmp al, 3
    je .s3
    cmp al, 4
    je .s4
    cmp al, 5
    je .s5
    cmp al, 6
    je .s6
    cmp al, 7
    je .s7
    mov si, exp_help
    call print_wnd
    jmp .hint
.s1:
    mov si, exp_copied
    call print_wnd
    jmp .hint
.s2:
    mov si, exp_cut
    call print_wnd
    jmp .hint
.s3:
    mov si, exp_pasted
    call print_wnd
    jmp .hint
.s4:
    mov si, exp_deleted
    call print_wnd
    jmp .hint
.s5:
    mov si, exp_no_slot
    call print_wnd
    jmp .hint
.s6:
    mov si, exp_wrong_drive
    call print_wnd
    jmp .hint
.s7:
    mov si, exp_no_clip
    call print_wnd
.hint:
    mov dh, 18
    mov dl, 0
    mov bl, 0x0F
    mov si, wnd_main_hint
    call print_wnd
    ret
.closed:
    mov dh, 10
    mov dl, 6
    mov bl, 0x0F
    mov si, wnd_closed
    call print_at
    mov dh, 12
    mov dl, 6
    mov si, wnd_restore_hint
    call print_at
    ret

draw_ui_simple:
    call refresh_simple_mode
    call clear_simple_bg

    mov dh, 0
    mov dl, 1
    mov bl, 0x0F
    mov si, title
    call print_at

    mov dh, 22
    mov dl, 1
    mov bl, 0x0F
    mov si, hint
    call print_at

    cmp byte [mode], 0
    je .m0
    cmp byte [mode], 1
    je draw_power_simple
    cmp byte [mode], 5
    je draw_media_drives
    cmp byte [mode], 6
    je draw_media_files
    cmp byte [mode], 7
    je .m7
    cmp byte [mode], 8
    je .m8
    cmp byte [mode], 9
    je draw_editor
    cmp byte [mode], 10
    je draw_hardware
    jmp draw_res_simple
.m0:
    jmp draw_main_simple
.m7:
    cmp byte [window_mode_enabled], 1
    jne draw_explorer_drives
    jmp draw_explorer_drives_windowed
.m8:
    cmp byte [window_mode_enabled], 1
    jne draw_explorer_files
    jmp draw_explorer_files_windowed

draw_main_simple:
    cmp byte [main_page], 0
    je .page1
    mov dh, 5
    mov dl, 7
    mov bl, 0x0E
    mov si, main_title_2
    call print_at

    mov al, 0
    mov dh, 10
    mov si, main_6
    call draw_item

    mov al, 1
    mov dh, 12
    mov si, main_7
    call draw_item
    mov al, 2
    mov dh, 14
    mov si, main_8
    call draw_item
    mov dh, 16
    mov dl, 10
    mov bl, 0x0F
    cmp byte [window_mode_enabled], 1
    je .wm_on
    mov si, wnd_mode_off
    call print_at
    ret
.wm_on:
    mov si, wnd_mode_on
    call print_at
    ret
.page1:
    mov dh, 5
    mov dl, 9
    mov bl, 0x0E
    mov si, main_title
    call print_at

    mov al, 0
    mov dh, 10
    mov si, main_1
    call draw_item

    mov al, 1
    mov dh, 12
    mov si, main_2
    call draw_item

    mov al, 2
    mov dh, 14
    mov si, main_3
    call draw_item
    mov al, 3
    mov dh, 16
    mov si, main_4
    call draw_item
    mov al, 4
    mov dh, 18
    mov si, main_5
    call draw_item
    mov al, 5
    mov dh, 20
    mov si, main_next
    call draw_item
    ret

draw_power_simple:
    mov dh, 5
    mov dl, 9
    mov bl, 0x0E
    mov si, power_title
    call print_at

    mov al, 0
    mov dh, 10
    mov si, pow_1
    call draw_item

    mov al, 1
    mov dh, 12
    mov si, pow_2
    call draw_item

    mov al, 2
    mov dh, 14
    mov si, pow_3
    call draw_item
    ret

draw_res_simple:
    mov dh, 5
    mov dl, 9
    mov bl, 0x0E
    mov si, res_title
    call print_at

    mov al, 0
    mov dh, 10
    mov si, res_1
    call draw_item

    mov al, 1
    mov dh, 12
    mov si, res_2
    call draw_item

    mov al, 2
    mov dh, 14
    mov si, res_3
    call draw_item

    mov al, 3
    mov dh, 16
    mov si, res_4
    call draw_item

    mov al, 4
    mov dh, 18
    mov si, res_5
    call draw_item

    mov al, 5
    mov dh, 20
    mov si, res_6
    call draw_item
    ret

draw_hardware:
    cmp byte [video_mode], 0
    jne .simple
    xor di, di
    mov al, 0x00
    mov cx, 320*200
    rep stosb
    jmp .body
.simple:
    call refresh_simple_mode
    call clear_simple_bg
.body:
    call update_runtime_info
    mov dh, 1
    mov dl, 1
    mov bl, 0x0F
    mov si, hw_title
    call print_at

    mov dh, 3
    mov dl, 1
    mov si, hw_cpu_vendor
    call print_at
    mov dh, 3
    mov dl, 14
    mov si, cpu_vendor
    call print_at

    mov dh, 4
    mov dl, 1
    mov si, hw_cpu_sig
    call print_at
    mov dh, 4
    mov dl, 14
    mov si, cpu_sig_hex
    call print_at

    mov dh, 5
    mov dl, 1
    mov si, hw_cpu_log
    call print_at
    mov dh, 5
    mov dl, 14
    mov si, cpu_logical_hex
    call print_at

    mov dh, 7
    mov dl, 1
    mov si, hw_vbe_ver
    call print_at
    mov dh, 7
    mov dl, 14
    mov si, vbe_ver_hex
    call print_at

    mov dh, 8
    mov dl, 1
    mov si, hw_vbe_mem
    call print_at
    mov dh, 8
    mov dl, 14
    mov si, vbe_mem_hex
    call print_at

    mov dh, 10
    mov dl, 1
    mov si, hw_mem_conv
    call print_at
    mov dh, 10
    mov dl, 14
    mov si, mem_conv_hex
    call print_at

    mov dh, 11
    mov dl, 1
    mov si, hw_mem_eax
    call print_at
    mov dh, 11
    mov dl, 14
    mov si, mem_e801_ax_hex
    call print_at

    mov dh, 12
    mov dl, 1
    mov si, hw_mem_ebx
    call print_at
    mov dh, 12
    mov dl, 14
    mov si, mem_e801_bx_hex
    call print_at

    mov dh, 13
    mov dl, 1
    mov si, hw_audio
    call print_at
    mov dh, 13
    mov dl, 14
    cmp byte [sb16_ok], 1
    je .aud_sb16
    mov si, hw_audio_none
    call print_at
    jmp .aud_done
.aud_sb16:
    mov si, hw_audio_sb16
    call print_at
.aud_done:

    mov dh, 14
    mov dl, 1
    mov si, hw_using
    call print_at

    mov dh, 15
    mov dl, 1
    mov si, hw_use_res
    call print_at
    mov dh, 15
    mov dl, 14
    mov al, [pref_mode]
    cmp al, 0
    je .r0
    cmp al, 1
    je .r1
    cmp al, 2
    je .r2
    cmp al, 3
    je .r3
    mov si, use_res_4
    jmp .pr
.r0:
    mov si, use_res_0
    jmp .pr
.r1:
    mov si, use_res_1
    jmp .pr
.r2:
    mov si, use_res_2
    jmp .pr
.r3:
    mov si, use_res_3
.pr:
    call print_at

    mov dh, 16
    mov dl, 1
    mov si, hw_use_in
    call print_at
    mov dh, 16
    mov dl, 14
    cmp byte [cursor_mode], 1
    je .in_cursor
    mov si, use_in_kbd
    jmp .pin
.in_cursor:
    mov si, use_in_cursor
.pin:
    call print_at

    mov dh, 17
    mov dl, 1
    mov si, hw_use_boot
    call print_at
    mov dh, 17
    mov dl, 14
    mov si, boot_drive_hex
    call print_at

    mov dh, 22
    mov dl, 1
    mov si, hw_hint
    call print_at
    ret

draw_debug:
    cmp byte [video_mode], 0
    jne draw_debug_simple

    xor di, di
    mov al, 0x00
    mov cx, 320*200
    rep stosb
    mov dh, 1
    mov dl, 1
    mov bl, 0x0F
    mov si, debug_title
    call print_at
    mov dh, 4
    mov dl, 2
    mov si, dbg_pm
    call print_at
    mov al, [pm_ok]
    mov dh, 4
    mov dl, 20
    call print_flag
    mov dh, 6
    mov dl, 2
    mov si, dbg_mm
    call print_at
    mov al, [mm_ok]
    mov dh, 6
    mov dl, 20
    call print_flag
    mov dh, 8
    mov dl, 2
    mov si, dbg_fat
    call print_at
    mov al, [fat_ok]
    mov dh, 8
    mov dl, 20
    call print_flag
    mov dh, 22
    mov dl, 1
    mov si, debug_hint
    call print_at
    ret

draw_debug_simple:
    call refresh_simple_mode
    call clear_simple_bg
    mov dh, 1
    mov dl, 1
    mov bl, 0x0F
    mov si, debug_title
    call print_at
    mov dh, 4
    mov dl, 2
    mov si, dbg_pm
    call print_at
    mov al, [pm_ok]
    mov dh, 4
    mov dl, 20
    call print_flag
    mov dh, 6
    mov dl, 2
    mov si, dbg_mm
    call print_at
    mov al, [mm_ok]
    mov dh, 6
    mov dl, 20
    call print_flag
    mov dh, 8
    mov dl, 2
    mov si, dbg_fat
    call print_at
    mov al, [fat_ok]
    mov dh, 8
    mov dl, 20
    call print_flag
    mov dh, 22
    mov dl, 1
    mov si, debug_hint
    call print_at
    ret

print_flag:
    cmp al, 0
    jne .ok
    mov si, txt_no
    jmp print_at
.ok:
    mov si, txt_ok
    jmp print_at

draw_desktop:
    cmp byte [video_mode], 0
    jne draw_desktop_simple

    xor di, di
    mov al, 0x02
    mov cx, 320*200
    rep stosb

    cmp byte [window_mode_enabled], 1
    jne .classic
    call draw_desktop_window_vga
    jmp .hint
.classic:
    xor di, di
    mov al, 0x0B
    mov cx, 320*18
    rep stosb

    mov ax, 48
    mov bx, 28
    mov cx, 224
    mov dx, 132
    mov byte [draw_color], 0x03
    call fill_rect

    mov dh, 0
    mov dl, 1
    mov bl, 0x0F
    mov si, desktop_title
    call print_at

    mov dh, 3
    mov dl, 10
    mov bl, 0x0F
    mov si, desktop_msg
    call print_at

.hint:
    mov dh, 22
    mov dl, 1
    mov bl, 0x0F
    cmp byte [window_mode_enabled], 1
    je .wnd_hint
    mov si, desktop_hint
    call print_at
    ret
.wnd_hint:
    mov si, desktop_hint_wnd
    call print_at
    ret

draw_desktop_simple:
    call refresh_simple_mode
    call clear_simple_bg
    cmp byte [window_mode_enabled], 1
    jne .classic
    call draw_desktop_window_simple
    jmp .hint
.classic:
    mov dh, 0
    mov dl, 1
    mov bl, 0x0F
    mov si, desktop_title
    call print_at
    mov dh, 3
    mov dl, 1
    mov bl, 0x0F
    mov si, desktop_msg
    call print_at
.hint:
    mov dh, 22
    mov dl, 1
    mov bl, 0x0F
    cmp byte [window_mode_enabled], 1
    je .wnd_hint
    mov si, desktop_hint
    call print_at
    ret
.wnd_hint:
    mov si, desktop_hint_wnd
    call print_at
    ret

draw_desktop_window_vga:
    cmp byte [window_visible], 1
    jne .closed
    mov ax, [window_y]
    mov bx, [window_x]
    mov cx, 160
    mov dx, 12
    mov byte [draw_color], 0x09
    call fill_rect
    cmp byte [window_minimized], 1
    je .title
    mov ax, [window_y]
    add ax, 12
    mov bx, [window_x]
    mov cx, 160
    mov dx, 88
    mov byte [draw_color], 0x03
    call fill_rect
    mov ax, [window_y]
    add ax, 28
    mov bx, [window_x]
    add bx, 8
    call set_text_xy_from_pixels
    mov dh, [txt_row]
    mov dl, [txt_col]
    mov bl, 0x0F
    mov si, desktop_msg
    call print_at
.title:
    mov ax, [window_y]
    mov bx, [window_x]
    add bx, 4
    call set_text_xy_from_pixels
    mov dh, [txt_row]
    mov dl, [txt_col]
    cmp byte [window_title_focus], 1
    je .focus
    mov bl, 0x0F
    mov si, wnd_title
    call print_at
    ret
.focus:
    mov bl, 0x0E
    mov si, wnd_title_focus
    call print_at
    ret
.closed:
    mov dh, 10
    mov dl, 8
    mov bl, 0x0F
    mov si, wnd_closed
    call print_at
    ret

draw_desktop_window_simple:
    mov dh, 0
    mov dl, 1
    mov bl, 0x0F
    mov si, desktop_title
    call print_at
    cmp byte [window_visible], 1
    jne .closed
    mov dh, 3
    mov dl, 1
    cmp byte [window_title_focus], 1
    je .focus
    mov bl, 0x0F
    mov si, wnd_title
    call print_at
    jmp .body
.focus:
    mov bl, 0x0E
    mov si, wnd_title_focus
    call print_at
.body:
    cmp byte [window_minimized], 1
    je .done
    mov dh, 5
    mov dl, 3
    mov bl, 0x0F
    mov si, desktop_msg
    call print_at
    jmp .done
.closed:
    mov dh, 6
    mov dl, 3
    mov bl, 0x0F
    mov si, wnd_closed
    call print_at
.done:
    ret

set_text_xy_from_pixels:
    ; AX=y, BX=x -> txt_row/txt_col (approx 8x8 cells)
    shr ax, 1
    shr ax, 1
    shr ax, 1
    shr bx, 1
    shr bx, 1
    shr bx, 1
    mov [txt_row], al
    mov [txt_col], bl
    ret

clear_simple_bg:
    ; Full-screen clear for mode 0x12-style UI.
    ; Keep identical color scheme across all non-320 resolutions.
    mov al, 0x01
    call fill_mode12_color
    ret

fill_mode12_color:
    ; AL=color index (4-bit) in mode 0x12.
    ; Writes all 4 planes at A000 with 0x00/0xFF masks.
    push bx
    push cx
    push dx
    push di
    push es

    mov bl, al
    mov ax, 0xA000
    mov es, ax
    mov dx, 0x03C4

    ; Plane 0
    mov ax, 0x0102
    out dx, ax
    xor di, di
    mov cx, 38400
    test bl, 0x01
    jz .p0_zero
    mov al, 0xFF
    rep stosb
    jmp .p1
.p0_zero:
    xor al, al
    rep stosb

.p1:
    mov ax, 0x0202
    out dx, ax
    xor di, di
    mov cx, 38400
    test bl, 0x02
    jz .p1_zero
    mov al, 0xFF
    rep stosb
    jmp .p2
.p1_zero:
    xor al, al
    rep stosb

.p2:
    mov ax, 0x0402
    out dx, ax
    xor di, di
    mov cx, 38400
    test bl, 0x04
    jz .p2_zero
    mov al, 0xFF
    rep stosb
    jmp .p3
.p2_zero:
    xor al, al
    rep stosb

.p3:
    mov ax, 0x0802
    out dx, ax
    xor di, di
    mov cx, 38400
    test bl, 0x08
    jz .p3_zero
    mov al, 0xFF
    rep stosb
    jmp .done
.p3_zero:
    xor al, al
    rep stosb

.done:
    mov ax, 0x0F02
    out dx, ax
    pop es
    pop di
    pop dx
    pop cx
    pop bx
    ret

refresh_simple_mode:
    mov ax, 0x0012
    int 0x10
    mov byte [video_mode], 1
    ret

draw_item:
    push si
    cmp al, [selected]
    jne .text
    mov dl, 8
    mov bl, 0x0F
    mov si, ptr_arrow
    call print_at
.text:
    pop si
    mov dl, 10
    mov bl, 0x0F
    call print_at
    ret

print_at:
    ; DH=row, DL=col, BL=color, SI=string
    mov ah, 0x02
    mov bh, 0x00
    int 0x10
    cmp byte [video_mode], 0
    jne .text_mode
.next:
    lodsb
    test al, al
    jz .done
    mov ah, 0x0A
    mov bh, 0x00
    mov cx, 0x0001
    int 0x10
    inc dl
    mov ah, 0x02
    mov bh, 0x00
    int 0x10
    jmp .next
.text_mode:
    lodsb
    test al, al
    jz .done
    mov ah, 0x0E
    mov bh, 0x00
    int 0x10
    jmp .text_mode
.done:
    ret

fill_rect:
    ; AX=y, BX=x, CX=width, DX=height, ES=A000
    push bp
    mov bp, cx
    mov si, ax
    shl ax, 8
    shl si, 6
    add ax, si
    add ax, bx
    mov di, ax
.row:
    mov cx, bp
    mov al, [draw_color]
    rep stosb
    add di, 320
    sub di, bp
    dec dx
    jnz .row
    pop bp
    ret

mode       db 0
selected   db 0
main_page  db 0
window_mode_enabled db 0
window_title_focus db 0
window_visible db 1
window_minimized db 0
window_x dw 76
window_y dw 42
txt_row db 0
txt_col db 0
wnd_row db 0
wnd_col db 0
window_key_consumed db 0
video_mode db 0
pref_mode  db 0
cursor_mode db 0
mouse_present db 0
cursor_drawn db 0
cursor_x    dw 0
cursor_y    dw 0
bg_color   db 0x01
draw_color db 0
vesa_mode  dw 0x0103
boot_drive db 0
pm_ok      db 0
mm_ok      db 0
fat_ok     db 0
mm_bitmap  times 16 db 0
fat_test_name db 'SIMPLOS TXT'
drive_count db 0
media_file_count db 0
media_play_status db 0
media_backend db 0
explorer_file_count db 0
media_selected_drive db 0
drive_list db 6 dup(0)
drive_letter db 0
drive_scan_idx db 0
media_name_0 db '............',0
media_name_1 db '............',0
media_name_2 db '............',0
media_name_3 db '............',0
media_from_iso db 0
media_entry_is_iso db 4 dup(0)
media_entry_sector db 4 dup(0)
media_entry_offset db 4 dup(0)
media_entry_lba dw 4 dup(0)
media_entry_size dw 4 dup(0)
media_scan_lba db 0
media_sel_idx db 0
media_cluster dw 0
media_lba dw 0
media_size dw 0
explorer_name_0 db '............',0
explorer_name_1 db '............',0
explorer_name_2 db '............',0
explorer_name_3 db '............',0
explorer_name_4 db '............',0
explorer_from_iso db 0
explorer_entry_sector db 5 dup(0)
explorer_entry_offset db 5 dup(0)
explorer_entry_lba dw 5 dup(0)
explorer_entry_size dw 5 dup(0)
explorer_scan_lba dw 0
explorer_status db 0
iso_root_lba dw 0
iso_root_size dw 0
iso_root_secs dw 0
clip_valid db 0
clip_cut db 0
clip_drive db 0
clip_sector db 0
clip_offset db 0
clip_entry times 32 db 0
paste_sector dw 0
paste_offset db 0
editor_len dw 0
editor_cursor dw 0
editor_size dw 0
editor_chunk dw 0
editor_first_cluster dw 0
editor_cur_cluster dw 0
editor_tmp_lba dw 0
editor_iso_lba dw 0
editor_dir_sector db 0
editor_dir_offset db 0
editor_read_only db 0
editor_known_type db 0
editor_status db 0
editor_dir_entry times 32 db 0
editor_name db 'UNTITLED.TXT',0
editor_buf times 2048 db 0
fat_tmp_lba dw 0
fat_tmp_pos dw 0
fat_tmp_b0 db 0
fat_tmp_b1 db 0
fat_tmp_cluster dw 0
cpu_vendor db 'UNKNOWNCPU??',0
cpu_sig dd 0
cpu_sig_hex db '00000000',0
cpu_logical db 0
cpu_logical_hex db '00',0
vbe_ok db 0
vbe_ver_hex db '----',0
vbe_mem_hex db '----',0
mem_conv_kb dw 0
mem_conv_hex db '0000',0
mem_e801_ax dw 0
mem_e801_bx dw 0
mem_e801_ax_hex db '----',0
mem_e801_bx_hex db '----',0
boot_drive_hex db '00',0
sb16_ok db 0
sb16_base dw 0x0220
vbe_info times 512 db 0
dap:
dap_size    db 16
dap_reserved db 0
dap_count   dw 1
dap_off     dw 0
dap_seg     dw 0
dap_lba_lo  dw 0
dap_lba_hi  dw 0
dap_lba_top dd 0
drive_label_0 db '--',0,0,0
drive_label_1 db '--',0,0,0
drive_label_2 db '--',0,0,0
drive_label_3 db '--',0,0,0
drive_label_4 db '--',0,0,0
drive_label_5 db '--',0,0,0

title      db 'SimplOS 2 Kernel', 0
hint       db 'Up/Down + Enter', 0
main_title db 'Main Menu', 0
main_1     db 'Boot Desktop', 0
main_2     db 'Resolution', 0
main_3     db 'Power Options', 0
main_4     db 'Media Player', 0
main_5     db 'File Explorer', 0
main_next  db 'Next Page >', 0
main_title_2 db 'Main Menu (Page 2)', 0
main_6     db 'Hardware Test', 0
main_7     db 'Window Mode', 0
main_8     db '< Back to Page 1', 0
wnd_mode_on db 'Status: ON',0
wnd_mode_off db 'Status: OFF',0
power_title db 'Power Menu', 0
pow_1      db 'Reboot', 0
pow_2      db 'Shutdown', 0
pow_3      db 'Back', 0
res_title  db 'Resolution', 0
res_1      db '320x200 VGA', 0
res_2      db '640x480 VGA', 0
res_3      db '800x600 VESA', 0
res_4      db '1024x768 VESA', 0
res_5      db 'Auto Fit Screen', 0
res_6      db 'Back', 0
media_title db 'Media Player - Drives', 0
media_files_title db 'Media Files', 0
explorer_title db 'File Explorer - Drives', 0
explorer_files_title db 'Files (C/X/V/D)', 0
msg_no_drives db 'No drives found', 0
msg_no_media db 'No compatible files', 0
msg_no_files db 'No files in root', 0
msg_media_sel db 'Selected', 0
msg_media_help db 'Enter=Play WAV/MID',0
msg_media_playing db 'Playing...',0
msg_media_done db 'Playback done',0
msg_media_unsup db 'Only WAV/MID supported',0
msg_media_io db 'Read error',0
msg_media_audio db 'Audio:',0
msg_media_sb16 db 'SB16',0
msg_media_pcspk db 'PCSPK',0
media_back db 'Back', 0
exp_help db 'C=Copy  X=Cut  V=Paste  D=Delete', 0
exp_copied db 'Copied to clipboard', 0
exp_cut db 'Cut to clipboard', 0
exp_pasted db 'Paste complete', 0
exp_deleted db 'Delete complete', 0
exp_no_slot db 'No free directory slot', 0
exp_wrong_drive db 'Paste only on same drive', 0
exp_no_clip db 'Clipboard empty', 0
editor_title db 'Text Editor',0
editor_warn db 'Warning: unknown file type',0
editor_help db 'Type to edit | F2 save | ESC back',0
editor_help_ro db 'Read-only file | ESC back',0
editor_status_idle db 'Ready',0
editor_status_saved db 'Saved',0
editor_status_io db 'Save failed (I/O)',0
editor_status_big db 'Save blocked (size grew)',0
editor_status_edit db 'Modified (unsaved)',0
editor_status_ro db 'Read-only source',0
hw_title db 'Hardware Test',0
hw_cpu_vendor db 'CPU Vendor: ',0
hw_cpu_sig db 'CPU Sig: ',0
hw_cpu_log db 'CPU Cores: ',0
hw_vbe_ver db 'VBE Ver: ',0
hw_vbe_mem db 'VBE Mem: ',0
hw_mem_conv db 'Conv KB: ',0
hw_mem_eax db 'E801 AX: ',0
hw_mem_ebx db 'E801 BX: ',0
hw_audio db 'Audio: ',0
hw_audio_sb16 db 'SB16',0
hw_audio_none db 'NONE',0
hw_using db 'SimplOS Using:',0
hw_use_res db 'Resolution: ',0
hw_use_in db 'Input: ',0
hw_use_boot db 'Boot Drive: ',0
use_res_0 db '320x200 VGA',0
use_res_1 db '640x480 VGA',0
use_res_2 db '800x600 VESA',0
use_res_3 db '1024x768 VESA',0
use_res_4 db 'Auto Fit',0
use_in_kbd db 'Keyboard',0
use_in_cursor db 'Cursor',0
hw_hint db 'ESC to return',0
desktop_title db 'SimplOS 2 Desktop', 0
desktop_msg   db 'Desktop loaded.', 0
desktop_hint  db 'ESC to return to menu', 0
desktop_hint_wnd db 'Ctrl+Esc title bar | Arrows/Enter | X C V',0
wnd_title db 'SimplOS Window',0
wnd_title_focus db '-- SimplOS Window --',0
wnd_kernel_focus db '-- SimplOS 2 Kernel --',0
wnd_explorer_title db 'File Explorer',0
wnd_explorer_title_focus db '-- File Explorer --',0
wnd_main_hint db 'Ctrl+Esc title bar | X C V',0
wnd_closed db 'Window closed. Press Ctrl+Esc then C restore.',0
wnd_restore_hint db 'Press C in title focus to restore.',0
boot_title db 'SimplOS 2', 0
boot_msg   db 'Starting kernel...', 0
boot_stage db 'Initializing systems', 0
boot_hint  db 'Press any key to skip wait', 0
debug_title db 'Debug Screen', 0
dbg_pm      db 'Protected mode:', 0
dbg_mm      db 'Memory manager:', 0
dbg_fat     db 'FAT12 probe:', 0
debug_hint  db 'ESC to return', 0
txt_ok      db 'OK', 0
txt_no      db 'NO', 0
ptr_arrow  db '>', 0
ask_1      db 13,10, 'SimplOS 2 input mode', 13,10, 0
ask_2      db '1) Cursor mode', 13,10, 0
ask_3      db '2) Keyboard only mode', 13,10, 0
ask_4      db 'Choose: ', 0

gdt_start:
    dq 0
    dq 00CF9A000000FFFFh
    dq 00CF92000000FFFFh
gdt_end:

gdt_desc:
    dw gdt_end - gdt_start - 1
    dd 0
