genrule(name="smoledcom",
        srcs=["smoled.asm"],
        outs=["smoled.com"],
        cmd="nasm -fbin $(SRCS) -o $@; ls -l $@",
)

genrule(name="smoledcomdebug",
        srcs=["smoled.asm"],
        outs=["smoledb.com"],
        cmd="nasm -fbin $(SRCS) -o $@ -dDEBUG; ls -l $@",
)
