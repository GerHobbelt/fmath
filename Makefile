GCC_VER=$(shell $(CXX) -dumpversion)
ifeq ($(shell expr $(GCC_VER) \>= 4.2),1)
    ADD_OPT+=-march=native
endif
ifeq ($(shell expr $(GCC_VER) \>= 4.5),1)
    ADD_OPT+=-fexcess-precision=fast
endif
AVX2=$(shell head -27 /proc/cpuinfo 2>/dev/null |awk '/avx2/ {print $$1}')
ifeq ($(AVX2),flags)
	HAS_AVX2=-mavx2
endif
PYTHON?=python3
# ----------------------------------------------------------------
INC_DIR= -I../src -I../xbyak -I./include
CFLAGS += $(INC_DIR) -O3 $(HAS_AVX2) $(ADD_OPT) -DNDEBUG
CFLAGS_WARN=-Wall -Wextra -Wformat=2 -Wcast-qual -Wcast-align -Wwrite-strings -Wfloat-equal -Wpointer-arith
CFLAGS+=$(CFLAGS_WARN)
ifeq ($(NEW),1)
  CFLAGS+=-DFMATH_NEW
endif
# ----------------------------------------------------------------

HEADER= fmath.hpp

TARGET=bench fastexp
all:$(TARGET)

.SUFFIXES: .cpp

bench: bench.o
	$(CXX) -o $@ $<

fastexp: fastexp.o
	$(CXX) -o $@ $<

avx2: avx2.cpp fmath.hpp
	$(CXX) -o $@ $< -O3 -mavx2 -mtune=native -Iinclude

exp_v: exp_v.cpp fmath2.hpp
	$(CXX) -o $@ $< -O3 -Iinclude -I../xbyak $(CFLAGS)
log_v: log_v.cpp fmath2.hpp
	$(CXX) -o $@ $< -O3 -Iinclude -I../xbyak $(CFLAGS)

new_exp_v: exp_v.o fmath.o
	$(CXX) -o $@ exp_v.o fmath.o

new_log_v: log_v.o fmath.o
	$(CXX) -o $@ log_v.o fmath.o

EXP_MODE?=allreg
EXP_UN?=4
unroll_test_n: exp_v.o
	@$(PYTHON) gen_fmath.py -m gas -exp_un $(EXP_UN) -exp_mode $(EXP_MODE) > fmath$(EXP_UN).S
	@$(CXX) -o exp_v$(EXP_UN).exe exp_v.o fmath$(EXP_UN).S $(CFLAGS)
	@./exp_v$(EXP_UN).exe b
	@./exp_v$(EXP_UN).exe b
	@./exp_v$(EXP_UN).exe b
	@./exp_v$(EXP_UN).exe b
	@./exp_v$(EXP_UN).exe b
	@./exp_v$(EXP_UN).exe b
	@./exp_v$(EXP_UN).exe b
	@./exp_v$(EXP_UN).exe b
	@./exp_v$(EXP_UN).exe b
	@./exp_v$(EXP_UN).exe b

unroll_test: exp_v.o
	@sh -ec 'for i in 1 2 3 4 5 6 7 8; do echo EXP_UN=$$i; make -s unroll_test_n EXP_UN=$$i; done'

fmath.o: fmath.S
	$(CC) -c $< -o $@

fmath.S: gen_fmath.py
	$(PYTHON) gen_fmath.py -m gas -exp_mode $(EXP_MODE) > fmath.S

.cpp.o:
	$(CXX) -c $< -o $@ $(CFLAGS)

.c.o:
	$(CXX) -c $< -o $@ $(CFLAGS)

clean:
	$(RM) *.o $(TARGET) exp_v log_v *.S *.exe

test: exp_v
	./exp_v

bench.o: bench.cpp $(HEADER)
fastexp.o: fastexp.cpp $(HEADER)

