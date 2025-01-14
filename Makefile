# top-level Makefile for debbugs
# probably requires GNU make to run properly

sbin_dir	:= $(DESTDIR)/usr/sbin
etc_dir		:= $(DESTDIR)/etc/debbugs
var_dir		:= $(DESTDIR)/var/lib/debbugs
scripts_dir	:= $(DESTDIR)/usr/lib/debbugs
doc_dir		:= $(DESTDIR)/usr/share/doc/debbugs
templates_dir	:= $(DESTDIR)/usr/share/debbugs/templates
man_dir		:= $(DESTDIR)/usr/share/man
man8_dir	:= $(man_dir)/man8
examples_dir	:= $(doc_dir)/examples

scripts_in	= $(foreach script, $(filter-out scripts/config% scripts/errorlib scripts/text, $(wildcard scripts/*)),$(patsubst scripts/%,%,$(script)))
htmls_in	:= $(wildcard html/*.html.in)
cgis		:= $(wildcard cgi/*.cgi)

install_exec	:= install -m755 -p
install_data	:= install -m644 -p

PERL ?= /usr/bin/perl
# Some tests need to run under an UTF-8 locale.
UTF8_LOCALE ?= C.UTF-8

all: build

build:
	$(PERL) Makefile.PL
	$(MAKE) -f Makefile.perl
# Don't bother to make the logo; it's not necessary
#       $(MAKE) -C html/logo

test:
	LC_ALL=$(UTF8_LOCALE) $(PERL) -MTest::Harness -Ilib -e 'runtests(glob(q(t/*.t)))'

test_%: t/%.t
	LC_ALL=$(UTF8_LOCALE) $(PERL) -MTest::Harness -Ilib -e 'runtests(q($<))'

testcover:
	LC_ALL=$(UTF8_LOCALE) PERL5LIB=t/cover_lib/:. cover -test

clean:
	if [ -e Makefile.perl ]; then \
		$(MAKE) -f Makefile.perl clean; \
	fi;

install: install_mostfiles
	# install basic debbugs documentation
	$(install_data) COPYING UPGRADE.md README.md debian/README.mail $(doc_dir)
	$(MAKE) -f Makefile.perl install DESTDIR=$(DESTDIR)

install_mostfiles:
	# create the directories if they aren't there
	for dir in $(sbin_dir) $(etc_dir)/html $(etc_dir)/indices \
$(var_dir)/indices $(var_dir)/www/cgi $(var_dir)/www/db $(var_dir)/www/txt \
$(var_dir)/www/css \
$(var_dir)/spool/lock $(var_dir)/spool/archive $(var_dir)/spool/incoming \
$(var_dir)/spool/db-h $(scripts_dir) $(examples_dir) $(man8_dir); \
          do test -d $$dir || $(install_exec) -d $$dir; done

	# install the scripts
	$(foreach script,$(scripts_in), $(install_exec) scripts/$(script) $(scripts_dir);)
	$(install_data) scripts/errorlib $(scripts_dir)/errorlib

	# install examples
	$(install_data) examples/config $(examples_dir)/config
	$(install_data) examples/config.debian $(examples_dir)/config.debian
	$(install_data) scripts/text $(examples_dir)/text
	$(install_data) debian/crontab misc/nextnumber misc/Maintainers \
	  misc/Maintainers.override misc/pseudo-packages.description \
	  misc/sources $(examples_dir)
	$(install_data) examples/apache.conf $(examples_dir)

	# install the HTML pages etc
	$(foreach html, $(htmls_in), $(install_data) $(html) $(etc_dir)/html;)
	$(install_data) html/htaccess $(var_dir)/www/db/.htaccess
	$(install_data) html/bugs.css $(var_dir)/www/css/bugs.css
	$(install_data) html/logo/debbugs_logo_icon.png $(var_dir)/www/favicon.png

	# install the CGIs
	for cgi in $(cgis); do $(install_exec) $$cgi $(var_dir)/www/cgi; done

	# install debbugsconfig
	$(install_exec) debian/debbugsconfig $(sbin_dir)
	$(install_data) debian/debbugsconfig.8 $(man8_dir)
	# install migration tools
	$(install_exec) migrate/debbugs-dbhash $(sbin_dir)
	$(install_data) migrate/debbugs-dbhash.8 $(man8_dir)
	$(install_exec) migrate/debbugs-upgradestatus $(sbin_dir)

	# install the updateseqs file
	$(install_data) misc/updateseqs $(var_dir)/spool

	# install the templates
	$(foreach dir, $(wildcard templates/*/*), $(install_exec) -d $(templates_dir)/$(patsubst templates/%,%,$(dir));)
	$(foreach tmpl, $(wildcard templates/*/*/*.tmpl), $(install_data) $(tmpl) $(templates_dir)/$(patsubst templates/%,%,$(tmpl));)


.PHONY: test build
