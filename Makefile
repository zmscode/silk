c:
	@clear
	@rm -rf zig-out

b:
	@clear
	@zig build

r:
	@clear
	@zig build run

rc:
	@make c
	@make r

t:
	@clear
	@zig build test