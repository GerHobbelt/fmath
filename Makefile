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
INC_DIR= -I../src -I../xbyak -I./include
CFLAGS += $(INC_DIR) -O3 $(HAS_AVX2) $(ADD_OPT) -DNDEBUG
CFLAGS_WARN=-Wall -Wextra -Wformat=2 -Wcast-qual -Wcast-align -Wwrite-strings -Wfloat-equal -Wpointer-arith
CFLAGS+=$(CFLAGS_WARN)
LDFLAGS+=fmath.o

#SRC=$(shell ls *.cpp)
SRC=exp_v.cpp log_v.cpp
DEP=$(SRC:.cpp=.d)
-include $(DEP)

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

EXP_MODE?=allreg
EXP_UN?=4
exp_unroll_n: exp_v.o
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

exp_unroll: exp_v.o
	@sh -ec 'for i in 1 2 3 4 5 6 7 8; do echo EXP_UN=$$i; make -s exp_unroll_n EXP_UN=$$i; done'

LOG_MODE?=allreg
LOG_UN?=4
log_unroll_n: log_v.o
	@$(PYTHON) gen_fmath.py -m gas -log_un $(LOG_UN) -log_mode $(LOG_MODE) > fmath$(LOG_UN).S
	@$(CXX) -o log_v$(LOG_UN).exe log_v.o fmath$(LOG_UN).S $(CFLAGS)
	@./log_v$(LOG_UN).exe b
	@./log_v$(LOG_UN).exe b
	@./log_v$(LOG_UN).exe b
	@./log_v$(LOG_UN).exe b
	@./log_v$(LOG_UN).exe b
	@./log_v$(LOG_UN).exe b
	@./log_v$(LOG_UN).exe b
	@./log_v$(LOG_UN).exe b
	@./log_v$(LOG_UN).exe b
	@./log_v$(LOG_UN).exe b

log_unroll: log_v.o
	@sh -ec 'for i in 1 2 3 4 5; do echo LOG_UN=$$i; make -s log_unroll_n LOG_UN=$$i; done'

fmath.o: fmath.S
	$(CC) -c $< -o $@

fmath.S: gen_fmath.py
	$(PYTHON) gen_fmath.py -m gas -exp_mode $(EXP_MODE) > fmath.S

%.o: %.cpp
	$(CXX) -o $@ $< -c $(CFLAGS) -MMD -MP -MF $(@:.o=.d)

%.exe: %.o fmath.o
	$(CXX) -o $@ $< $(LDFLAGS)

clean:
	$(RM) *.o $(TARGET) *.exe *.S

test: exp_v
	./exp_v

bench.o: bench.cpp $(HEADER)
fastexp.o: fastexp.cpp $(HEADER)

# don't remove these files automatically
.SECONDARY: $(addprefix $(OBJ_DIR)/, $(ALL_SRC:.cpp=.o))
