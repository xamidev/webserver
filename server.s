# HTTP GET/POST concurrent webserver targeting Linux ABI for x86_64 processors
# This code is public domain
# Author: xamidev

.intel_syntax noprefix
.global _start

.equ AF_INET, 2
.equ SOCK_STREAM, 1
.equ NULL, 0
.equ O_RDONLY, 0
.equ O_WRONLY, 1
.equ O_CREAT, 64 

.section .text

_start:
	# write(unsigned int fd, char* buf, size_t count)
	mov rax, 1
	mov rdi, 1
	lea rsi, [rip + str_welcome]
	mov rdx, 24
	syscall

	# socket(AF_INET, SOCK_STREAM, NULL)
	mov rax, 41
	mov rdi, AF_INET
	mov rsi, SOCK_STREAM
	mov rdx, NULL
	syscall

	# Save sockfd somewhere
	mov r8, rax

	# bind(int sockfd, struct sockaddr_in*, int addrlen)
	mov rax, 49
	mov rdi, r8
	lea rsi, [rip + sockaddr_in]
	mov rdx, 16
	syscall

	# listen(int sockfd, int backlog)
	mov rax, 50
	mov rdi, r8
	mov rsi, 0 
	syscall

	.accept_incoming_connections:
		# accept(int sockfd, struct sockaddr_in*, int* addrlen)
		mov rax, 43
		mov rdi, r8
		mov rsi, NULL
		mov rdx, NULL
		syscall

		# Save sockfd to close it later
		mov r14, rax

	# fork() -> new child process for incoming connection; PID in rax
	mov rax, 57
	syscall

	# If return value is zero, we're in the child process: we can process the connection
	# If return value is non-zero, we're in the parent process: we have to get back to accepting incoming connections

	test rax, rax
	jz .continue
	jmp .close_actual_sockfd

	.close_actual_sockfd:
		# close(unsigned int fd)
		mov rax, 3
		mov rdi, r14
		syscall
		jmp .accept_incoming_connections

	.continue:	
		# close(unsigned int fd)
		mov rax, 3
		mov rdi, r8
		syscall
	
		# read(unsigned int fd, char* buf, size_t count)
		mov rax, 0
		mov rdi, r14
		lea rsi, [rip + request_buf]
		mov rdx, 1024
		syscall	

		# Save read bytes (full request size)
		mov r13, rax
	
		.parse_http_path:
			# Parse the HTTP request
			# When one space is found, extract bytes until next space
			lea rsi, [rip + request_buf]
			xor rcx, rcx
			.find_start:
				mov al, byte [rsi + rcx]
				cmp al, ' '
				je .path_start
				inc rcx
				jmp .find_start

			.path_start:
				inc rcx
				lea rdi, [rsi+rcx]
				xor rdx, rdx
			.path_loop:
				mov al, byte [rdi + rdx]
				cmp al, ' '
				je .path_done
				mov byte [path_buf + rdx], al
				inc rdx
				jmp .path_loop
			.path_done:

		# Detect if request is GET or POST (first char is G: GET, else POST)
		.parse_get_post:
			lea rsi, [rip + request_buf]
			mov al, byte [rsi]
			cmp al, 69 # 'E' (2nd letter, rsi+1)
			je .get_request
			jmp .post_request

		.post_request:
			# open(const char* filename, int flags, int mode)
			mov rax, 2
			lea rdi, [path_buf+1]
			mov rsi, O_WRONLY | O_CREAT # O_RDONLY for GET requests
			mov rdx, 0x1FF # All permissions	
			syscall

			# Save fd
			mov r10, rax

			.parse_request_content:
				# When we find \r\n\r\n we know that the content follows.
				# request_buf already contains full request.
				lea rsi, [rip + request_buf]
				xor rcx, rcx
				
				.find_body:
					mov al, byte [rsi+rcx]
					cmp al, 13 # \r
					jne .next
					mov al, byte [rsi+rcx+1]
					cmp al, 10 # \n
					jne .next
					mov al, byte [rsi+rcx+2]
					cmp al, 13
					jne .next
					mov al, byte[rsi+rcx+3]
					cmp al, 10
					jne .next

					add rcx, 4
					jmp .body_found	
				
				.next:
					# Threshold to avoid infinite looping if request is malformed
					inc rcx
					cmp rcx, 512
					jl .find_body

					jmp .error_exit

				.body_found:
					lea rdi, [rsi+rcx]
					lea rsi, [rip+request_content_buf]
					mov rbx, r13
					sub rbx, rcx
					mov r13, rbx

					# Byte amount of request content is now in r13			
					# Now we copy this to a buffer
					xor rcx, rcx

					.content_copy_loop:
						cmp rcx, r13
						jge .done_copy

						mov al, byte [rdi+rcx]
						mov byte [rsi+rcx], al
						inc rcx
						jmp .content_copy_loop
					.done_copy:
					dec r13	
					# Byte length in r13 (decrement cause of null-byte)
					# Content in request_content_buf				

			# Here, as we have a POST request, we will have to write to filename instead of reading from it.

			# write(unsigned int fd, const char* buf, size_t count)
			mov rax, 1
			mov rdi, r10
			lea rsi, [rip + request_content_buf+1] # ADDRESS OF REQUEST CONTENT BUFFER		
			mov rdx, r13 # AMOUNT OF BYTES IN REQUEST CONTENT		
			syscall

			# Save read bytes
			mov r15, rax

			# close(unsigned int fd)
			mov rax, 3
			mov rdi, r10
			syscall

			# We simply return a 200 OK here

			# write(unsigned int fd, const char* buf, size_t count)
			mov rax, 1
			mov rdi, r14
			lea rsi, [rip + response]
			mov rdx, 19
			syscall

			# close(unsigned int fd)
			mov rax, 3
			mov rdi, r14
			syscall	
			
			jmp .normal_exit

		.get_request:
			# open(const char* filename, int flags, int mode)
			mov rax, 2
			lea rdi, [path_buf+1]
			mov rsi, O_RDONLY
			mov rdx, NULL # who cares?
			syscall

			# Save fd
			mov r10, rax

			# read(unsigned int fd, char* buf, size_t count)
			mov rax, 0
			mov rdi, r10
			lea rsi, [rip + file_buf]
			mov rdx, 1024
			syscall

			# Save read bytes
			mov r15, rax
	
			# close(unsigned int fd)
			mov rax, 3
			mov rdi, r10
			syscall

			# write(unsigned int fd, const char* buf, size_t count)
			mov rax, 1
			mov rdi, r14
			lea rsi, [rip + response]
			mov rdx, 19
			syscall	

			# write(unsigned int fd, const char* buf, size_t count)
			mov rax, 1
			mov rdi, r14
			lea rsi, [rip + file_buf]
			mov rdx, r15
			syscall
			
			# close(unsigned int fd)
			mov rax, 3
			mov rdi, r14
			syscall	

		.normal_exit:
			# exit(0)
			mov rax, 60
			mov rdi, 0
			syscall

		.error_exit:
			mov rax, 60
			mov rdi, -1
			syscall

.section .data

response:
	.asciz "HTTP/1.0 200 OK\r\n\r\n"

str_welcome:
	.asciz "Starting HTTP server...\n"

# Total size: 16 bytes
sockaddr_in:
	.word AF_INET
	# Port 80 = 0x0050 (unsigned short, 2 bytes)
	# Big endian: bytes are in reverse order
	.word 0x5000
	# 32-bits of zeroes: 0.0.0.0
	.int 0x00000000
	.zero 8

.section .bss

path_buf:
	.zero 64

request_buf:
	.zero 1024

file_buf:
	.zero 1024

stat_buf:
	.zero 1024

request_content_buf:
	.zero 1024
