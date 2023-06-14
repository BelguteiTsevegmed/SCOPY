; Purpose of each register:
; rax - used for system call numbers and return values
; rdi - used for arguments to system calls, sometimes as input file descriptor
; rsi - used for arguments to system calls, sometimes points to buffer
; rdx - used for arguments to system calls, sometimes as buffer size
; r10 - used as output buffer index
; r9w - used as counter for number of characters between 's' or 'S'
; r15 - used to hold number of bytes read from file
; r12 - used as index into buffer
; r8b - used to hold current character from buffer

section .text
    global _start

_start:
    ; Check number of arguments
    pop rax ; argc
    cmp rax, 3  ; Compare with expected number of arguments
    jne error  ; If not equal to 3, jump to error

    ; Open file for reading
    mov rax, 2  ; sys_open syscall number
    mov rdi, [rsp + 8] ; argv[1] - file name is second argument
    xor rsi, rsi  ; O_RDONLY mode
    xor rdx, rdx
    syscall
    cmp rax, 0
    jl error  ; If file opening failed, jump to error
    mov [input_fd], rax

    ; Create file for writing
    mov rax, 2  ; sys_open syscall number
    mov rdi, [rsp + 16] ; argv[2] - file name is third argument
    mov rsi, 0xC1  ; O_WRONLY | O_CREAT | O_EXCL mode
    mov rdx, 0644o  ; permissions -rw-r--r--
    syscall
    cmp rax, 0
    jl error  ; If file creation failed, jump to error
    mov [output_fd], rax

    ; Read from file
    mov rax, 0  ; sys_read syscall number
    movzx rdi, word [input_fd]  ; Input file descriptor
    lea rsi, [buffer]  ; Buffer
    mov rdx, BUFF_LEN  ; Buffer size
    syscall
    cmp rax, 0
    jl error  ; If read failed, jump to error
    mov r15, rax  ; Save number of bytes read

    ; Check if we've reached the end of the file
    cmp rax, 0  ; rax holds the number of bytes read, it will be 0 at the end of the file
    je eof  ; If we've reached the end of the file, jump to eof

    ; Zero out the counter
    mov r9w, 0

parse_buffer:
    xor r12, r12  ; Zero out r12, we'll use this as our index

next_char:
    cmp r12, r15  ; Check if we've reached the end of the bytes read
                  ; (r15 holds the number of bytes read)
    je read_next  ; If we have, jump to read the next part of the file
    mov r8b, byte [buffer + r12]  ; Load the current character into r8

    ; Check if the character is 's' or 'S'
    mov rbx, s
    cmp r8b, [rbx]
    je write_to_file

    inc rbx
    cmp r8b, [rbx]
    je write_to_file

    inc r9w  ; Increase the counter
    inc r12  ; Increase the index
    jmp next_char  ; Continue to the next character

write_to_file:
    ; Check if the counter is zero
    cmp r9w, 0
    je s_or_S  ; If the counter is zero, jump to s_or_S

    ; Write counter to the buffer
    mov byte [rel out_buff + r10], r9b  ; First byte of the counter
    inc r10  ; Increment the out_buffer index
    shr r9w, 8  ; Shift right by 8 bits to get the second byte of the counter
    mov byte [rel out_buff + r10], r9b  ; Second byte of the counter
    inc r10  ; Increment the out_buff index
    
    ; Reset counter
    xor r9w, r9w

s_or_S:
    ; Write 's' or 'S' to the buffer
    mov byte [rel out_buff + r10], r8b
    inc r10  ; Increment the out_buff index

    ; Write the whole sequence to the file
    mov rax, 1  ; sys_write syscall number
    mov rdi, [output_fd]  ; Output file descriptor
    lea rsi, [out_buff]  ; Buffer with the counter in little endian and the 's'
    mov rdx, r10
    syscall

    ; Check for write error
    cmp rax, r10
    jne error  ; If write failed (if anything other than one character was written), jump to error

    ; Go back to parse the buffer
    xor r10, r10  ; r10 = 0
    inc r12  ; Increment the buffer index to include s or S
    jmp next_char

read_next:
    ; Read the next part of the file into the buffer
    mov rax, 0  ; sys_read
    movzx rdi, word [input_fd]
    lea rsi, [buffer]
    mov rdx, BUFF_LEN
    syscall
    cmp rax, 0
    jl error  ; If read failed, jump to error
    mov r15, rax  ; Save number of bytes read
    
    ; Check if we've reached the end of the file
    cmp rax, 0  ; rax holds the number of bytes read, it will be 0 at the end of the file
    je eof  ; If we've reached the end of the file, jump to eof

    ; If we haven't reached the end of the file jump back to parse_buffer
    jmp parse_buffer

eof:
    ; If the counter is zero, no need to write anything
    cmp r9w, 0
    je close_files

    ; Write counter to the buffer
    mov byte [rel out_buff + r10], r9b  ; First byte of the counter
    inc r10  ; Increment the buffer index
    shr r9w, 8  ; Shift right by 8 bits to get the second byte of the counter
    mov byte [rel out_buff + r10], r9b  ; Second byte of the counter
    inc r10  ; Increment the buffer index

    ; Write the whole sequence to the file
    mov rax, 1  ; sys_write syscall number
    mov rdi, [output_fd]  ; Output file descriptor
    lea rsi, [out_buff]  ; Buffer with the counter in little endian and the 's'
    mov rdx, r10
    syscall

    ; Check for write error
    cmp rax, r10
    jne error  ; If write failed (if anything other than one character was written), jump to error

close_files:
    mov rax, 3  ; sys_close syscall number
    movzx rdi, word [input_fd]  ; Input file descriptor
    syscall
    cmp rax, 0
    jne error  ; If input file closing failed, jump to error

    mov rax, 3 ; sys_close syscall number
    movzx rdi, word [output_fd]  ; Output file descriptor
    syscall
    cmp rax, 0
    jne error  ; If output file closing failed, jump to error

    ; Exit program
    mov rax, 60 ; sys_exit syscall number
    xor rdi, rdi
    syscall

error:
    ; Exit program with error code 1
    mov rax, 60  ; sys_exit syscall number
    mov rdi, 1  ; Error code
    syscall

section .data
    BUFF_LEN equ 4096  ; I thought that 4096 bytes will be optimal for thus buffer
    buffer: times BUFF_LEN db 0
    s: db 's', 'S', 0, 0  ; Here I keep the value of "s" and "S"
    OUT_BUFF_LEN equ 3  ; The size of the buffer is 3 bytes, because we will
                        ; keep maximally 3 bytes in this buffer (2 bytes for
                        ; the number of characters between "s" and 1 byte for 
                        ; the "s")
    out_buff times OUT_BUFF_LEN db 0
section .bss
    input_fd:   resd 1  ; File descriptor for the input file
    output_fd:  resd 1  ; File descriptor for the output file
