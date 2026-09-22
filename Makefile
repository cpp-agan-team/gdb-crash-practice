CXX := g++
CXXFLAGS := -std=c++17 -O0 -g3 -fno-omit-frame-pointer -Wall -Wextra -Wpedantic -pthread
CASES := 01_segfault 02_deadlock 03_infinite_loop 04_wrong_result 05_watchpoint 06_exception
TARGETS := $(addprefix build/,$(CASES))

.PHONY: all verify list
all: $(TARGETS)

build:
	mkdir -p build

build/%: cases/%/main.cpp Makefile | build
	$(CXX) $(CXXFLAGS) $< -o $@

verify: all
	python3 scripts/verify.py

list:
	@printf '%s\n' $(CASES)
