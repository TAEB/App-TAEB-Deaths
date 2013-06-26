package App::TAEB::Deaths;
use Moose;

with 'MooseX::SimpleConfig';
with 'MooseX::Getopt::Dashes';

use POE qw(Component::IRC);
use Getopt::Long;
use YAML;

use File::Spec;
use File::HomeDir;
use Cwd 'abs_path';

has '+configfile' => (
    default => sub {
        my $taebdir = $ENV{TAEBDIR};
        $taebdir ||= File::Spec->catdir(File::HomeDir->my_home, '.taeb');
        $taebdir = abs_path($taebdir);
        return File::Spec->catdir($taebdir, 'deaths.yml') if -d $taebdir;
        mkdir $taebdir, 0700 or do {
            local $SIG{__DIE__} = 'DEFAULT';
            die "Please create a $taebdir directory.\n";
        };
        return File::Spec->catdir($taebdir, 'deaths.yml');
    },
);

has server => (
    is       => 'rw',
    isa      => 'Str',
    required => 1,
);

has nick => (
    is       => 'rw',
    isa      => 'Str',
    required => 1,
);

has username => (
    is       => 'rw',
    isa      => 'Str',
    required => 1,
);

has from => (
    is       => 'rw',
    isa      => 'ArrayRef[HashRef]',
    required => 1,
);

has watch => (
    is      => 'rw',
    isa     => 'HashRef',
    default => sub { {} },
);

has to => (
    is       => 'rw',
    isa      => 'Str',
    required => 1,
);

has session => (
    is       => 'ro',
    isa      => 'POE::Session',
    lazy     => 1,
    required => 1,
    default  => sub {
        my $self = shift;

        POE::Session->create(
            object_states => [
                $self => [
                    qw(
                      _start
                      irc_001
                      irc_public
                      irc_registered
                    )
                ],
            ],
        );
    },
);

sub _start {
    my ($self, $kernel, $session) = @_[OBJECT, KERNEL, SESSION];

    POE::Component::IRC->spawn(
        nick     => $self->nick,
        username => $self->username,
        server   => $self->server,
    ) or die "Unable to spawn POE::Component::IRC: $!";

    $kernel->signal($kernel, 'POCOIRC_REGISTER', $session->ID(), 'all');
}

sub irc_registered {
    my ($self, $irc) = @_[OBJECT, ARG0];

    $irc->yield(connect => {});
}

sub irc_001 {
    my ($self, $sender) = @_[OBJECT, SENDER];
    my $irc = $sender->get_heap();

    for my $chan (@{ $self->from }) {
        my $channel = $chan->{channel};
        $self->watch->{$channel} = $chan;
        $self->watch->{$channel}->{_watch} = {};
        $self->watch->{$channel}->{_watch}->{lc $_} = 1 for @{$chan->{watch}};
        $irc->yield(join => $channel);
    }

    $irc->yield(join => $self->to);
}

sub irc_public {
    my ($self, $sender, $who, $where, $msg) = @_[OBJECT, SENDER, ARG0..ARG2];

    my $nick = (split '!', $who)[0];
    my $channel = $where->[0];

    # Check that the message is in the right channel.
    return unless exists $self->watch->{$channel};

    # Check that the message in the channel is from the right nick.
    my $watched = $self->watch->{$channel};
    return unless $nick eq $watched->{announcer};

    # Check that it's a death message.
    my $death_re = $watched->{death_re};
    my $re = qr/$death_re/;
    return unless $msg =~ $re;

    # The death regex should have a capture around the nick. Check that that
    # nick is a desired death to relay.
    return unless $watched->{_watch}->{lc $1};

    # Everything has passed, so relay the message!
    my $irc = $sender->get_heap();
    $irc->yield(privmsg => $self->to => $msg);
}


sub run {
    POE::Kernel->post($_[0]->session => '_start');
    POE::Kernel->run();
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
