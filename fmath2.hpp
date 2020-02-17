#pragma once
/**
	@author herumi
	@note modified new BSD license
	http://opensource.org/licenses/BSD-3-Clause
*/
#include <xbyak/xbyak_util.h>
#include <cmath>

namespace fmath2 {

namespace local {

union fi {
	float f;
	uint32_t i;
};

inline float cvt(uint32_t x)
{
	fi fi;
	fi.i = x;
	return fi.f;
}

struct ExpData {
	static const size_t TaylerN = 5;
	float minX; // exp(minX) = 0
	float maxX; // exp(maxX) = inf
	float log2; // log(2)
	float log2_e; // log_2(e) = 1 / log2
	float c[TaylerN]; // near to 1/(i + 1)!
	void init()
	{
		minX = cvt(0xc2aeac50);
		maxX = cvt(0x42b17218);
		log2 = std::log(2.0f);
		log2_e = 1.0f / log2;
#if 0
		// maxe=4.888831e-06
		float z = 1;
		for (size_t i = 0; i < TaylerN; i++) {
			c[i] = z;
			z /= (i + 2);
		}
#else
		// maxe=1.938668e-06
		const uint32_t tbl[TaylerN] = {
			0x3f800000,
			0x3effff12,
			0x3e2aaa56,
			0x3d2b89cc,
			0x3c091331,
		};
		for (size_t i = 0; i < TaylerN; i++) {
			c[i] = cvt(tbl[i]);
		}
#endif
	}
};

/*
The constans c are generated by Maple.
f := x->A+B*x+C*x^2+D*x^3+E*x^4+F*x^5;
g:=int((f(x)-exp(x))^2,x=-L..L);
sols:=solve({diff(g,A)=0,diff(g,B)=0,diff(g,C)=0,diff(g,D)=0,diff(g,E)=0,diff(g,F)=0},{A,B,C,D,E,F});
Digits:=1000;
s:=eval(sols,L=log(2)/2);
evalf(s,20);
*/
struct Code : public Xbyak::CodeGenerator {
	Xbyak::util::Cpu cpu;
	ExpData *expData;
	void (*expf_v)(float *, size_t);
	Code()
		: Xbyak::CodeGenerator(4096 * 2, Xbyak::DontSetProtectRWE)
	{
		if (!cpu.has(Xbyak::util::Cpu::tAVX512F)) {
			fprintf(stderr, "AVX-512 is not supported\n");
			exit(1);
		}
		size_t dataSize = sizeof(ExpData);
		dataSize = (dataSize + 4095) & ~size_t(4095);
		Xbyak::Label expDataL = L();
		expData = (ExpData*)getCode();
		expData->init();
		setSize(dataSize);
		expf_v = getCurr<void (*)(float *, size_t)>();
		genExp(expDataL);
		setProtectModeRE();
	}
	~Code()
	{
		setProtectModeRW();
	}
	void genExp(const Xbyak::Label& expDataL)
	{
		using namespace Xbyak;
		util::StackFrame sf(this, 2, 0, 64 * 9);
		const Reg64& px = sf.p[0];
		const Reg64& n = sf.p[1];

		// prolog
#ifdef XBYAK64_WIN
		vmovups(ptr[rsp + 64 * 0], zm6);
		vmovups(ptr[rsp + 64 * 1], zm7);
#endif
		for (int i = 2; i < 9; i++) {
			vmovups(ptr[rsp + 64 * i], Zmm(i + 6));
		}

		// setup constant
		const Zmm& i127 = zmm5;
		const Zmm& minX = zmm6;
		const Zmm& maxX = zmm7;
		const Zmm& log2 = zmm8;
		const Zmm& log2_e = zmm9;
		const Zmm c[] = { zmm10, zmm11, zmm12, zmm13, zmm14 };
		mov(eax, 127);
		vpbroadcastd(i127, eax);
		vpbroadcastd(minX, ptr[rip + expDataL + (int)offsetof(ExpData, minX)]);
		vpbroadcastd(maxX, ptr[rip + expDataL + (int)offsetof(ExpData, maxX)]);
		vpbroadcastd(log2, ptr[rip + expDataL + (int)offsetof(ExpData, log2)]);
		vpbroadcastd(log2_e, ptr[rip + expDataL + (int)offsetof(ExpData, log2_e)]);
		for (size_t i = 0; i < ExpData::TaylerN; i++) {
			vpbroadcastd(c[i], ptr[rip + expDataL + (int)(offsetof(ExpData, c[0]) + sizeof(float) * i)]);
		}

		// main loop
	Xbyak::Label lp = L();
		vmovups(zm0, ptr[px]);
		vminps(zm0, maxX);
		vmaxps(zm0, minX);
		vmulps(zm0, log2_e);
		vrndscaleps(zm1, zm0, 0); // n = floor(x)
		vsubps(zm0, zm1); // a
		vcvtps2dq(zm1, zm1);
		vmulps(zm0, log2);
		vpaddd(zm1, zm1, i127);
		vpslld(zm1, zm1, 23); // fi.f
		vmovaps(zm2, c[4]);
		vfmadd213ps(zm2, zm0, c[3]);
		vfmadd213ps(zm2, zm0, c[2]);
		vfmadd213ps(zm2, zm0, c[1]);
		vfmadd213ps(zm2, zm0, c[0]);
		vfmadd213ps(zm2, zm0, c[0]);
		vmulps(zm0, zm2, zm1);

		vmovups(ptr[px], zm0);
		add(px, 64);
		sub(n, 16);
		jnz(lp, T_NEAR);

		// epilog
#ifdef XBYAK64_WIN
		vmovups(zm6, ptr[rsp + 64 * 0]);
		vmovups(zm7, ptr[rsp + 64 * 1]);
#endif
		for (int i = 2; i < 9; i++) {
			vmovups(Zmm(i + 6), ptr[rsp + 64 * i]);
		}
	}
};

template<size_t dummy = 0>
struct C {
	static const Code code;
};

template<size_t dummy>
MIE_ALIGN(32) const Code C<dummy>::code;

} // fmath::local

inline float split(int *pn, float x)
{
	int n;
	if (x >= 0) {
		n = int(x + 0.5f);
	} else {
		n = int(x - 0.5f);
	}
	*pn = n;
	return x - n;
}

inline float expfC(float x)
{
	const local::ExpData& C = *local::C<>::code.expData;
	x = (std::min)(x, C.maxX);
	x = (std::max)(x, C.minX);
	x *= C.log2_e;
	int n;
	float a = split(&n, x);
	/* |a| <= 0.5 */
	a *= C.log2;
	/* |a| <= 0.3466 */
	local::fi fi;
	fi.i = (n + 127) << 23; // 2^n
	/*
		e^a = 1 + a + a^2/2! + a^3/3! + a^4/4! + a^5/5!
		= 1 + a(1 + a(1/2! + a(1/3! + a(1/4! + a/5!))))
	*/
	x = C.c[4];
	x = a * x + C.c[3];
	x = a * x + C.c[2];
	x = a * x + C.c[1];
	x = a * x + C.c[0];
	x = a * x + C.c[0];
	return x * fi.f;
}

inline void expf_vC(float *px, size_t n)
{
	for (size_t i = 0; i < n; i++) {
		px[i] = expfC(px[i]);
	}
}

inline void expf_v(float *px, size_t n)
{
	size_t n16 = n & ~size_t(15);
	if (n16 > 0) {
		local::C<>::code.expf_v(px, n16);
	}
	size_t n15 = n & 15;
	if (n15 == 0) return;
	px += n16;
	float cp[16];
	for (size_t i = 0; i < n15; i++) {
		cp[i] = px[i];
	}
	for (size_t i = n15; i < 16; i++) {
		cp[i] = 0; // clear is not necessary
	}
	local::C<>::code.expf_v(cp, 16);
	for (size_t i = 0; i < n15; i++) {
		px[i] = cp[i];
	}
}

} // fmath2
