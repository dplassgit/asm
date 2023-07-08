genrule(name="smoledcom",
        srcs=["smoled.asm"],
        outs=["smoled.com"],
        cmd="nasm -fbin $(SRCS) -o $@",
)

genrule(name="keytestcom",
        srcs=["keytest.asm"],
        outs=["keytest.com"],
        cmd="nasm -fbin $(SRCS) -o $@",
)
