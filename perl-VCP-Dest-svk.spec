%define		pnam	VCP-Dest-svk
Summary:	svk destination driver
Summary(pl.UTF-8):	Sterownik celu svk
Name:		perl-VCP-Dest-svk
Version:	0.29
Release:	1
# same as perl
License:	GPL v1+ or Artistic
Group:		Development/Languages/Perl
Source0:	http://www.cpan.org/modules/by-authors/id/C/CL/CLKAO/%{pnam}-%{version}.tar.gz
# Source0-md5:	c4b3fb8f9bb159d6e3010ae86cae54e1
BuildRequires:	perl-SVK >= 0.20
BuildRequires:	perl-VCP >= 0.9
BuildRequires:	perl-devel >= 1:5.8.0
BuildRequires:	rpm-perlprov >= 4.1-13
BuildArch:	noarch
BuildRoot:	%{tmpdir}/%{name}-%{version}-root-%(id -u -n)

%description
svk destination driver.

%description -l pl.UTF-8
Sterownik celu svk.

%prep
%setup -q -n %{pnam}-%{version}

%build
%{__perl} Makefile.PL \
	INSTALLDIRS=vendor
%{__make}

%{?with_tests:%{__make} test}

%install
rm -rf $RPM_BUILD_ROOT

%{__make} install \
	DESTDIR=$RPM_BUILD_ROOT

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(644,root,root,755)
%dir %{perl_vendorlib}/VCP/Dest
%{perl_vendorlib}/VCP/Dest/*.pm
%{_mandir}/man3/*
