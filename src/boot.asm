BITS 16
ORG 0x7C00

KERNEL_SEGMENT equ 0x1000
KERNEL_LBA     equ 33
KERNEL_SECTORS equ 32

    jmp short start
    nop
    db 'SIMPLOS2'
    dw 512
    db 1
    dw 1
    db 2
    dw 224
    dw 2880
    db 0F0h
    dw 9
    dw 18
    dw 2
    dd 0
    dd 0
    db 0
    db 0
    db 29h
    dd 1234ABCDh
    db 'SIMPLOS2   '
    db 'FAT12   '

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti

    mov [boot_drive], dl
    xor ax, ax
    mov ds, ax
    mov [0x0500], dl
    mov ax, 0x07C0
    mov ds, ax

    mov si, msg_loading
    call print_string

    xor bx, bx
    mov ax, KERNEL_SEGMENT
    mov es, ax
    mov di, KERNEL_LBA
    mov cx, KERNEL_SECTORS

load_loop:
    push cx
    push di

    mov ax, di
    call lba_to_chs

    mov ah, 0x02
    mov al, 0x01
    mov dl, [boot_drive]
    int 0x13
    jnc read_ok

    mov ah, 0x00
    mov dl, [boot_drive]
    int 0x13

    mov ax, di
    call lba_to_chs
    mov ah, 0x02
    mov al, 0x01
    mov dl, [boot_drive]
    int 0x13
    jc disk_error

read_ok:
    add bx, 512
    pop di
    inc di
    pop cx
    loop load_loop

    jmp KERNEL_SEGMENT:0x0000

disk_error:
    mov si, msg_disk_error
    call print_string
halt:
    cli
    hlt
    jmp halt

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

print_string:
    lodsb
    test al, al
    jz .done
    mov ah, 0x0E
    mov bh, 0x00
    mov bl, 0x0F
    int 0x10
    jmp print_string
.done:
    ret

boot_drive    db 0
msg_loading   db 'Loading kernel...', 0
msg_disk_error db 13,10, 'Disk read failed.', 0

times 510-($-$$) db 0
dw 0xAA55
