%include	/usr/lib/rpm/macros.perl
%define		pnam	VCP-Dest-svk
Summary:	svk destination driver
Summary(pl):	Sterownik celu svk
Name:		perl-VCP-Dest-svk
Version:	0.24
Release:	1
# same as perl
License:	GPL v1+ or Artistic
Group:		Development/Languages/Perl
Source0:	http://search.cpan.org/CPAN/authors/id/C/CL/CLKAO/%{pnam}-%{version}.tar.gz	
# Source0-md5:	834b035fa882516e8db73d64c9b26527
BuildRequires:	perl-VCP
BuildRequires:	perl-devel >= 1:5.8.0
BuildRequires:	rpm-perlprov >= 4.1-13
BuildArch:	noarch
BuildRoot:	%{tmpdir}/%{name}-%{version}-root-%(id -u -n)

%description
svk destination driver.

%description -l pl
Sterownik celu svk.

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
