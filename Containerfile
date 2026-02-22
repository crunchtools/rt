# =============================================================================
# Stage 1: Build RT and compile CPAN dependencies
# =============================================================================
FROM quay.io/crunchtools/ubi8-httpd-perl AS builder

RUN --mount=type=secret,id=activation_key \
    --mount=type=secret,id=org_id \
    if [ -f /run/secrets/activation_key ] && [ -f /run/secrets/org_id ]; then \
        subscription-manager register \
            --activationkey="$(cat /run/secrets/activation_key)" \
            --org="$(cat /run/secrets/org_id)" && \
        subscription-manager attach --auto; \
    fi

RUN yum install -y expat-devel gcc make mod_fcgid mailx && yum clean all

RUN subscription-manager unregister 2>/dev/null || true

# Install CPAN dependencies (THE SLOW LAYER — cached by Docker)
RUN cpan -i CPAN
RUN cpan -i -f GnuPG::Interface
RUN cpan -i DBIx::SearchBuilder \
    ExtUtils::Command::MM \
    Text::WikiFormat \
    Devel::StackTrace \
    Apache::Session \
    Module::Refresh \
    HTML::TreeBuilder \
    HTML::FormatText::WithLinks \
    HTML::FormatText::WithLinks::AndTables \
    Data::GUID \
    CGI::Cookie \
    DateTime::Format::Natural \
    Text::Password::Pronounceable \
    UNIVERSAL::require \
    JSON \
    DateTime \
    Net::CIDR \
    CSS::Minifier::XS \
    CGI \
    Devel::GlobalDestruction \
    Text::Wrapper \
    Net::IP \
    HTML::RewriteAttributes \
    Log::Dispatch \
    Plack \
    Regexp::Common::net::CIDR \
    Scope::Upper \
    CGI::Emulate::PSGI \
    HTML::Mason::PSGIHandler \
    HTML::Scrubber \
    HTML::Entities \
    HTML::Mason \
    File::ShareDir \
    Mail::Header \
    XML::RSS \
    List::MoreUtils \
    Plack::Handler::Starlet \
    IPC::Run3 \
    Email::Address \
    Role::Basic \
    MIME::Entity \
    Regexp::IPv6 \
    Convert::Color \
    Business::Hours \
    Symbol::Global::Name \
    MIME::Types \
    Locale::Maketext::Fuzzy \
    Tree::Simple \
    Clone \
    HTML::Quoted \
    Data::Page::Pageset \
    Text::Quoted \
    DateTime::Locale \
    HTTP::Message \
    Crypt::Eksblowfish \
    Data::ICal \
    Locale::Maketext::Lexicon \
    Time::ParseDate \
    Mail::Mailer \
    Email::Address::List \
    Date::Extract \
    CSS::Squish \
    Class::Accessor::Fast \
    LWP::Simple \
    Module::Versions::Report \
    Regexp::Common \
    Date::Manip \
    CGI::PSGI \
    JavaScript::Minifier::XS \
    FCGI \
    PerlIO::eol \
    GnuPG::Interface \
    "LWP::UserAgent >= 6.02" \
    LWP::Protocol::https \
    String::ShellQuote \
    Crypt::X509

# Download and install RT 4.4.4
RUN curl -fsSL https://download.bestpractical.com/pub/rt/release/rt-4.4.4.tar.gz | tar xz -C /root
RUN cd /root/rt-4.4.4 && ./configure
RUN cd /root/rt-4.4.4 && make testdeps && make install

# =============================================================================
# Stage 2: Deploy (lean runtime image)
# =============================================================================
FROM quay.io/crunchtools/ubi8-httpd-perl

RUN yum install -y postfix mailx && yum clean all
RUN systemctl enable postfix

# Copy RT from builder
COPY --from=builder /opt/rt4 /opt/rt4
COPY --from=builder /usr/lib64/perl5 /usr/lib64/perl5
COPY --from=builder /usr/share/perl5 /usr/share/perl5
COPY --from=builder /usr/local/share/perl5 /usr/local/share/perl5
COPY --from=builder /usr/local/lib64/perl5/ /usr/local/lib64/perl5/

# Fix ownership
RUN chown -R root:bin /opt/rt4/lib && chown -R root:apache /opt/rt4/etc

# Copy init scripts, systemd units, and config files
COPY rootfs/ /

# Enable init services
RUN chmod +x /usr/local/bin/rt-db-prep.sh /usr/local/bin/rt-db-setup.sh && \
    systemctl enable rt-db-prep rt-db-setup

ENTRYPOINT ["/sbin/init"]
