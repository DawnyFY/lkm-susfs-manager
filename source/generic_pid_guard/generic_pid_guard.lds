SECTIONS {
	__patchable_function_entries : { *(__patchable_function_entries) }
	.text : {
		init_module.cfi_jt = . + 0x3c0;
		gp_ret.cfi_jt = . + 0x3c8;
		cleanup_module.cfi_jt = . + 0x3d0;
	}
}
