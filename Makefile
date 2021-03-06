cn_secboot	= Secure Boot CA
cn_vendor	= Vendor CA

all : secboot.key secboot.crt secboot.db vendor.key vendor.crt \
      shim.efi ipxe.efi Shell.secboot.efi Shell.vendor.efi

#
# Construct self-signed certificates
#

%.key :
	openssl genrsa -out $@ 2048
.PRECIOUS : %.key

%.crt : %.key
	openssl req -x509 -key $< -subj '/CN=$(cn_$*)' -days 3000 -out $@

%.der : %.crt
	openssl x509 -in $< -outform DER -out $@

#
# Construct DB signature list file
#

%.siglist : %.der
	sbsiglist --owner $(shell uuidgen) --type x509 --output $@ $<

%.db : %.siglist %.key %.crt
	sbvarsign --key $*.key --cert $*.crt --output $@ sb $<

#
# Build shim and sign with Secure Boot key
#

multi.der : vendor.der fedora.der
	cat $^ > $@

shim/shimx64.efi : multi.der
	$(MAKE) -C shim VENDOR_CERT_FILE=$(CURDIR)/multi.der \
			DEFAULT_LOADER=ipxe.efi

shim.efi : shim/shimx64.efi secboot.key secboot.crt
	sbsign --key secboot.key --cert secboot.crt --output $@ $<

#
# Build iPXE and sign with vendor key
#

ipxe/src/% :
	$(MAKE) -C ipxe/src $*

ipxe.efi : ipxe/src/bin-x86_64-efi/ipxe.efi vendor.key vendor.crt
	sbsign --key vendor.key --cert vendor.crt --output $@ $<

#
# Sign UEFI shell with each key
#

Shell.efi :
	curl https://raw.githubusercontent.com/tianocore/edk2/master/ShellBinPkg/UefiShell/X64/Shell.efi -o $@

Shell.%.efi : Shell.efi %.key %.crt
	sbsign --key $*.key --cert $*.crt --output $@ $<

#
# Cleanup
#

clean :
	$(MAKE) -C shim clean
	rm -f secboot.*
	rm -f vendor.*
	rm -f *.der
	rm -f *.siglist
	rm -f *.sb
	rm -f *.efi
