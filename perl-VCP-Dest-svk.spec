%include	/usr/lib/rpm/macros.perl
%define	pnam	VCP-Dest-svk
Summary:	svk destination driver 
Name:		perl-VCP-Dest-svk
Version:	0.20
Release:	1
# same as perl
License:	GPL v1+ or Artistic
Group:		Development/Languages/Perl
Source0:	http://search.cpan.org/src/CLKAO/VCP-Dest-svk-0.20/svk.pm
# Source0-md5:	3c3fec2f99c75904f6ddf01eb5314dad
BuildRequires:	perl-VCP
BuildRequires:	perl-devel >= 1:5.8.0
BuildRequires:	rpm-perlprov >= 4.1-13
BuildArch:	noarch
BuildRoot:	%{tmpdir}/%{name}-%{version}-root-%(id -u -n)

%description
svk destination driver.

%prep

%install
rm -rf $RPM_BUILD_ROOT

install -D %{SOURCE0} $RPM_BUILD_ROOT%{perl_vendorlib}/VCP/Dest/svk.pm

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(644,root,root,755)
%dir %{perl_vendorlib}/VCP/Dest
%{perl_vendorlib}/VCP/Dest/*.pm
