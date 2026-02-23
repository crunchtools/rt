# =============================================================================
# Stage 1: Build RT and compile CPAN dependencies
# =============================================================================
FROM quay.io/crunchtools/ubi10-httpd-perl AS builder

RUN --mount=type=secret,id=activation_key \
    --mount=type=secret,id=org_id \
    if [ -s /run/secrets/activation_key ] && [ -s /run/secrets/org_id ]; then \
        subscription-manager register \
            --activationkey="$(cat /run/secrets/activation_key)" \
            --org="$(cat /run/secrets/org_id)"; \
    fi

RUN dnf install -y \
    expat-devel \
    gcc \
    make \
    openssl-devel \
    mariadb-connector-c-devel \
    perl-CPAN \
    perl-ExtUtils-MakeMaker \
    gnupg2 \
    && dnf clean all

RUN subscription-manager unregister 2>/dev/null || true

# Create mysql_config symlink for DBD::mysql 4.x (mariadb-connector-c provides mariadb_config)
RUN ln -sf /usr/bin/mariadb_config /usr/bin/mysql_config

# Install cpanm for reliable automated CPAN installs
RUN curl -fsSL https://cpanmin.us | perl - App::cpanminus

# Install CPAN dependencies for RT 6.0.2 (split into layers for caching)
# Layer 1: Core framework deps (Moose stack, DBI, DateTime)
RUN cpanm --notest \
    Moose \
    MooseX::NonMoose \
    MooseX::Role::Parameterized \
    namespace::autoclean \
    DBI

# DBD::mysql 4.050 has a my_bool/_Bool pointer type mismatch that GCC 14 treats as error
RUN PERL_MM_OPT="DEFINE=-Wno-error=incompatible-pointer-types" cpanm --notest DBD::mysql@4.050
RUN cpanm --notest DBD::MariaDB

RUN cpanm --notest \
    DBIx::SearchBuilder \
    DateTime \
    DateTime::Format::Natural \
    DateTime::Locale \
    DateTime::Set \
    Date::Extract \
    Date::Manip

# Layer 2: Web stack (HTML, CSS, HTTP, Mason, Plack)
RUN cpanm --notest \
    CGI \
    CGI::Cookie \
    CGI::Emulate::PSGI \
    CGI::PSGI \
    CSS::Inliner \
    CSS::Minifier::XS \
    CSS::Squish \
    FCGI \
    HTML::Entities \
    HTML::FormatExternal \
    HTML::FormatText::WithLinks \
    HTML::FormatText::WithLinks::AndTables \
    HTML::Gumbo \
    HTML::Mason \
    HTML::Mason::PSGIHandler \
    HTML::Quoted \
    HTML::RewriteAttributes \
    HTML::Scrubber \
    HTTP::Message \
    JavaScript::Minifier::XS \
    Plack \
    Plack::Handler::Starlet \
    Web::Machine \
    Path::Dispatcher

# Layer 3: Email, encoding, network, crypto
RUN cpanm --notest \
    Email::Address \
    Email::Address::List \
    Encode::Detect::Detector \
    Encode::HanExtra \
    LWP::Protocol::https \
    LWP::Simple \
    LWP::UserAgent \
    Mail::Header \
    Mail::Mailer \
    MIME::Entity \
    MIME::Types \
    Mozilla::CA \
    Net::CIDR \
    Net::IP \
    Crypt::Eksblowfish \
    GnuPG::Interface \
    PerlIO::eol

# Layer 4: Utilities and remaining deps
RUN cpanm --notest \
    Apache::Session \
    Business::Hours \
    Class::Accessor::Fast \
    Clone \
    Convert::Color \
    Data::GUID \
    Data::ICal \
    Data::Page \
    Devel::GlobalDestruction \
    Devel::StackTrace \
    File::ShareDir \
    Hash::Merge \
    Hash::Merge::Extra \
    Imager \
    IPC::Run3 \
    JSON \
    List::MoreUtils \
    Locale::Maketext::Fuzzy \
    Locale::Maketext::Lexicon \
    Log::Dispatch \
    Module::Path \
    Module::Refresh \
    Module::Runtime \
    Module::Versions::Report \
    Parallel::ForkManager \
    Regexp::Common \
    Regexp::Common::net::CIDR \
    Regexp::IPv6 \
    Role::Basic \
    Scope::Upper \
    Sub::Exporter \
    Symbol::Global::Name \
    Term::ReadKey \
    Text::Password::Pronounceable \
    Text::Quoted \
    Text::Template \
    Text::WikiFormat \
    Text::WordDiff \
    Text::Wrapper \
    Time::ParseDate \
    Tree::Simple \
    URI \
    XML::RSS

# Download and install RT 6.0.2
RUN curl -fsSL https://download.bestpractical.com/pub/rt/release/rt-6.0.2.tar.gz | tar xz -C /root
RUN cd /root/rt-6.0.2 && ./configure --with-db-type=MariaDB
RUN cd /root/rt-6.0.2 && make testdeps && make install

# =============================================================================
# Stage 2: Deploy (lean runtime image)
# =============================================================================
FROM quay.io/crunchtools/ubi10-httpd-perl

RUN dnf install -y postfix && dnf clean all
RUN systemctl enable postfix

# Copy RT from builder
COPY --from=builder /opt/rt6 /opt/rt6
COPY --from=builder /usr/lib64/perl5 /usr/lib64/perl5
COPY --from=builder /usr/share/perl5 /usr/share/perl5
COPY --from=builder /usr/local/share/perl5 /usr/local/share/perl5
COPY --from=builder /usr/local/lib64/perl5/ /usr/local/lib64/perl5/

# Fix ownership
RUN chown -R root:bin /opt/rt6/lib && chown -R root:apache /opt/rt6/etc

# RT 6.0.2 ships schema.mysql/acl.mysql but DatabaseType MariaDB looks for schema.MariaDB/acl.MariaDB
RUN ln -sf /opt/rt6/etc/schema.mysql /opt/rt6/etc/schema.MariaDB && \
    ln -sf /opt/rt6/etc/acl.mysql /opt/rt6/etc/acl.MariaDB

# Copy init scripts, systemd units, and config files
COPY rootfs/ /

# Enable init services
RUN chmod +x /usr/local/bin/rt-db-prep.sh /usr/local/bin/rt-db-setup.sh && \
    systemctl enable rt-db-prep rt-db-setup

ENTRYPOINT ["/sbin/init"]
