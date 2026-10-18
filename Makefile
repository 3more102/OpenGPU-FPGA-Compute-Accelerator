.PHONY: test test-python test-rtl test-synth assemble-demo clean

RTL_SOURCES = rtl/opengpu_alu.sv rtl/opengpu_scratchpad.sv rtl/opengpu_core.sv rtl/opengpu_program_rom.sv rtl/opengpu_top.sv rtl/opengpu_mmio.sv

test: test-python test-rtl test-synth

assemble-demo:
	mkdir -p build
	python tools/opengpu_asm.py examples/demo.ogasm --format hex --output build/demo.hex

test-python:
	python -m unittest discover -s tests -v

test-rtl:
	mkdir -p build
	iverilog -g2012 -s tb_opengpu_top -o build/opengpu_tb $(RTL_SOURCES) tb/tb_opengpu_top.sv
	vvp build/opengpu_tb
	iverilog -g2012 -s tb_opengpu_program_load -o build/opengpu_program_load_tb $(RTL_SOURCES) tb/tb_opengpu_program_load.sv
	vvp build/opengpu_program_load_tb
	iverilog -g2012 -s tb_opengpu_mmio -o build/opengpu_mmio_tb $(RTL_SOURCES) tb/tb_opengpu_mmio.sv
	vvp build/opengpu_mmio_tb
	iverilog -g2012 -s tb_opengpu_scratchpad_mmio -o build/opengpu_scratchpad_tb $(RTL_SOURCES) tb/tb_opengpu_scratchpad_mmio.sv
	vvp build/opengpu_scratchpad_tb
	python tools/gen_diff_vectors.py --outdir build
	iverilog -g2012 -s tb_opengpu_differential -o build/opengpu_diff_tb $(RTL_SOURCES) tb/tb_opengpu_differential.sv
	vvp build/opengpu_diff_tb +CASE=0
	vvp build/opengpu_diff_tb +CASE=1
	vvp build/opengpu_diff_tb +CASE=2
	vvp build/opengpu_diff_tb +CASE=3

test-synth:
	yosys -Q -p "read_verilog -sv $(RTL_SOURCES); hierarchy -check -top opengpu_mmio; synth -top opengpu_mmio -noabc; check"

clean:
	rm -rf build
