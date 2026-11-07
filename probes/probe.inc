// Shared by the hand-written gfx1100 probes. One kernel per file, one global pointer arg (kernarg s[0:1]),
// wave32, CU mode, workgroup id x in s2. Build: probes/build.sh
//   PROBE_BEGIN name        code follows, 256 B aligned
//   PROBE_END name, vgprs, lds   pad with s_code_end, then descriptor + metadata (vgprs = highest VGPR index + 1)
.macro PROBE_BEGIN name
	.text
	.globl \name
	.p2align 8
	.type \name,@function
\name:
.endm

.macro PROBE_END name, vgprs, lds
	.p2alignl 8, 0xbf9f0000
.Lend_\name:
	.size \name, .Lend_\name-\name
	.rodata
	.p2align 6
	.amdhsa_kernel \name
		.amdhsa_group_segment_fixed_size \lds
		.amdhsa_private_segment_fixed_size 0
		.amdhsa_kernarg_size 8
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_system_sgpr_workgroup_id_x 1
		.amdhsa_next_free_vgpr \vgprs
		.amdhsa_next_free_sgpr 8
		.amdhsa_wavefront_size32 1
		.amdhsa_workgroup_processor_mode 0
		.amdhsa_forward_progress 0
	.end_amdhsa_kernel
	.amdgpu_metadata
---
amdhsa.version: [1, 2]
amdhsa.kernels:
  - .name: \name
    .symbol: \name\().kd
    .args:
      - {.size: 8, .offset: 0, .value_kind: global_buffer, .address_space: global}
    .kernarg_segment_size: 8
    .kernarg_segment_align: 8
    .group_segment_fixed_size: \lds
    .private_segment_fixed_size: 0
    .wavefront_size: 32
    .sgpr_count: 8
    .vgpr_count: \vgprs
    .max_flat_workgroup_size: 1024
...
	.end_amdgpu_metadata
.endm

// fill_to START, BOUNDARY, INSN: repeat INSN until the code is BOUNDARY bytes past START
.macro fill_to start, boundary, insn:vararg
	.rept (\boundary - (. - \start)) / 4
		\insn
	.endr
.endm
