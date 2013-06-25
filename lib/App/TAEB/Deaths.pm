package App::TAEB::Deaths;
use Moose;

with 'MooseX::SimpleConfig';
with 'MooseX::Getopt::Dashes';

use POE qw(Component::IRC);
use Getopt::Long;
use YAML;

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

has from => (
    is       => 'rw',
    isa      => 'ArrayRef[HashRef]',
    required => 1,
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

    my $irc = POE::Component::IRC->spawn(
        nick   => $self->nick,
        server => $self->server,
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

    my @from_channels = map { $_->{channel} } @{ $self->from };
    $irc->yield(join => $_) for @from_channels;
}

sub irc_public {
}


sub run {
    POE::Kernel->post($_[0]->session => '_start');
    POE::Kernel->run();
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
