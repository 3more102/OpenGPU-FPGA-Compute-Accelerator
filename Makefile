.PHONY: test test-python test-rtl clean

RTL_SOURCES = rtl/opengpu_alu.sv rtl/opengpu_core.sv rtl/opengpu_program_rom.sv rtl/opengpu_top.sv

test: test-python test-rtl

test-python:
	python -m unittest discover -s tests -v

test-rtl:
	mkdir -p build
	iverilog -g2012 -s tb_opengpu_top -o build/opengpu_tb $(RTL_SOURCES) tb/tb_opengpu_top.sv
	vvp build/opengpu_tb

clean:
	rm -rf build
