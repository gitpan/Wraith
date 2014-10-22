use strict;
use warnings;

require Exporter;

our $VERSION = 0.11;

{
    package Wraith;

    our @ISA = qw( Exporter );
    our @EXPORT_OK = qw( $literal $literals $token $many $succeed $fail );

    {
        package inner_lazy;

        sub TIESCALAR {
            my ($class, $val) = @_;
            bless $_[1], $class
        }

        sub FETCH {
            my ($self) = @_;
            $self->()
        }
    }

    use overload
        '>>' => "then_impl",
        '|' => "alt_impl",
        '**' => "using_impl";

    sub deref {
        my @args = @_;
        for my $elt (@args) {
            if (ref($elt) eq "Wraith_rule") {
                $elt = $$elt;
            }
        }
        @args
    }

    sub concat_impl {
        my @list_of_lists = @_;
        my @list;

        for my $elt (@list_of_lists) {
            push @list, $_ for @$elt;
        }
        \@list
    };
    our $concat = \&concat_impl;

    sub succeed_impl {
        my $v = $_[0];
        bless
        sub {
            my $u = (ref($v) eq "ARRAY") ? $v : [ $v ];
            [ [ $u, $_[0] ] ]
        }
    };
    our $succeed = bless \&succeed_impl;

    sub fail_impl {
        []
    };
    our $fail = bless \&fail_impl;

    sub satisfy_impl {
        my ($p, $m) = @_;
        $m = sub { $_[0] =~ /(.)(.*)/s } if not $m;
        bless
        sub {
            if (my ($x, $xs) = $m->($_[0])) {
                if ($p->($x)) {
                    return $succeed->($x)->($xs);
                } else {
                    return $fail->($xs);
                }
            } else {
                return $fail->( [] );
            }
        }
    };
    our $satisfy = bless \&satisfy_impl;

    sub literal_impl {
        my $y = $_[0];
        $satisfy->( 
            sub { 
                $y eq $_[0] 
            }
        )
    };
    our $literal = bless \&literal_impl;

    sub literals_impl {
        my $y = $_[0];
        $satisfy->(
            sub {
                index($y, $_[0]) != -1
            }
        )
    };
    our $literals = bless \&literals_impl;

    sub token_impl {
        my ($tok, $skip) = @_;
        $skip = '\s*' if not $skip;
        $satisfy->(
            sub { 1 },
            sub {
                $_[0] =~ /^$skip($tok)(.*)/s
            }
        )
    };
    our $token = bless \&token_impl;

    sub alt_impl {
        my ($p1_, $p2_, $discard) = @_;
        bless
        sub {
            my ($p1, $p2) = deref($p1_, $p2_);
            my $inp = $_[0];
            $concat->($p1->($inp), $p2->($inp))
        }
    }
    our $alt = bless \&alt_impl;

    sub then_impl {
        my $arglist = \@_;
        bless
        sub {
            my ($p1) = deref($arglist->[0]);
            my $inp = $_[0];
            my $reslist1 = $p1->($inp);
            my $finlist = [];
            for my $respair (@$reslist1) {
                my ($p2) = deref($arglist->[1]);
                my $reslist2 = $p2->($respair->[1]);
                for my $finpair (@$reslist2) {
                    push @$finlist, [ $concat->($respair->[0], $finpair->[0]), $finpair->[1] ];
                }
            }
            $finlist
        }
    }
    our $then = bless \&then_impl;

    sub using_impl {
        my ($p_, $f, $discard) = @_;
        bless
        sub {
            my ($p) = deref($p_);
            my $inp = $_[0];
            my $reslist = $p->($inp);
            my $finlist = [];
            for my $respair (@$reslist) {
                push @$finlist, [ $f->($respair->[0]), $respair->[1] ];
            }
            $finlist
        }
    }
    our $using = bless \&using_impl;

    sub many_impl {
        my $p = $_[0];
        my $f;
        tie $f, "inner_lazy", sub { many_impl($p) };
        $alt->($then->($p, $f), $succeed->( [] ))
    }
    our $many = bless \&many_impl;
}

{
    package Wraith_rule;

    our @ISA = qw( Exporter Wraith );
    our @EXPORT_OK = qw( );

    sub makerule {
        bless $_[0]
    }

    sub makerules {
        my ($class, @args) = @_;
        for my $elt (@args) {
            $elt = makerule($elt);
        }
        @args
    }
}

1;

__END__

=encoding utf-8

=head1 NAME

Wraith - Parser Combinator in Perl

=head1 SYNOPSIS


    use Wraith qw ( $succeed $many $token );

    my ($E, $Etail, $T, $Ttail, $F, $num);
    Wraith_rule->makerules(\$E, \$Etail, \$T, \$Ttail, \$F, \$num);

    $E = ((\$T) >> (\$Etail)) ** sub { my ($tval, $etval) = @{$_[0]}; if ($etval) { return [ $etval->($tval) ]; } else { return [ $tval ] } };
    $Etail = (
                ( $token->('\+') >> (\$T) >> (\$Etail) ) **
                sub { 
                    my ($discard, $tval, $etval) = @{$_[0]};
                    if ($etval) {
                        return [ sub { $_[0] + $etval->($tval) } ];
                    } else {
                        return [ sub { $_[0] + $tval } ];
                    }
                }
             ) |
             (
                ( $token->('-') >> (\$T) >> (\$Etail) ) **
                sub { 
                    my ($discard, $tval, $etval) = @{$_[0]};
                    if ($etval) {
                        return [ sub { $_[0] - $etval->($tval) } ];
                    } else {
                        return [ sub { $_[0] - $tval } ];
                    }
                }
             ) |
             $succeed->( [] );
    $T = ((\$F) >> (\$Ttail)) ** sub { my ($fval, $ttval) = @{$_[0]}; if ($ttval) { return [ $ttval->($fval) ]; } else { return [ $fval ] } };
    $Ttail = (
                ( $token->('\*') >> (\$F) >> (\$Ttail) ) **
                sub { 
                    my ($discard, $fval, $ttval) = @{$_[0]};
                    if ($ttval) {
                        return [ sub { $ttval->($_[0] * $fval) } ];
                    } else {
                        return [ sub { $_[0] * $fval } ];
                    }
                }
             ) |
             (
                ( $token->('\/') >> (\$F) >> (\$Ttail) ) **
                sub { 
                    my ($discard, $fval, $ttval) = @{$_[0]};
                    if ($ttval) {
                        return [ sub { 
                                     if ($fval) { 
                                         return $ttval->($_[0] / $fval);
                                     } else { 
                                         return $_[0]; 
                                     } 
                                 } 
                               ];
                    } else {
                        return [ sub { if ($fval) { return $_[0] / $fval; } else { return $_[0] } } ];
                    }
                }
             ) |
             $succeed->( [] );
    $F = ( ( $token->('\(') >> (\$E) >> $token->('\)') ) ** sub { [ $_[0]->[1] ] } ) |
         (\$num);
    $num = $token->('[1-9][0-9]*');

    print $E->('1 + 13 / 2 * 3 + 2 * (2 + 3)')->[0]->[0]->[0], "\n";
    print $E->('2 * 3')->[0]->[0]->[0], "\n";

=head1 DESCRIPTION

Wraith is a simple parser combinator library (not monadic nor memoized) inspired
by Boost.Spirit. It is not complete as Spirit but the fundamental operators are
implemented.

When applied with arguments, all operators/combinators return a function, which 
takes a string as input sentence(s) and return a reference to a list of pairs:
[ $pair_1, $pair_2, ..., $pair_n ],
where each pair is a reference to a two-element list:
[ ref_to_list_of_results, input_unprocessed ],
in which ref_to_list_of_results is a reference to a list of analysis results and
input_unprocessed is a string representing the unprocessed input so far.


=head2 Basic Operators:

=head3 reference $succeed

It is a curried version of operator succeed. The first parameter of succeed is
the analysis result and the second parameter is the unprocessed input string.

=head3 reference $fail

It takes an argument, discards it and return an empty list.

Those two operators are rarely used. Use them if you need new combinators or empty matches.

=head3 reference $literal

It takes one character as the only argument. The returned function match the first 
character of its input against the argument character and return (argument, input_left)
if matched, where input_left is the input without its first character, or return
an empty list if failed to match.

=head3 reference $literals

Almost the same as $literal, but takes a string as the only argument and match
the first character of input with each character in argument string until matched.

=head3 reference $token

Takes a regex string as its first argument. The second and optional argument is a
regex string of skipped strings. It matches the regex at the beginning of the
input string, return (token, input_left) if matched or an empty list if failed.

=head2 Combinators:

There are four combinators: then for sequence, alt for alternative, many for kleene
star and using for semantic actions. Except many, the combinators are overloaded
perl operators which takes at least one operator, combinator, compsite of combinators,
product, or reference to an instance of those classes as the left-hand-side operand.

The returned list of function generated by combinators is a list of tokens in the
order of they appeared in the products.

=head3 operator >> 

Sequence combinator. For example, the product S -> T S would be written as
    $S = \$T >> $S;
where $S and $T are rules, i.e, products.

=head3 operator | 

Alternative combinator. For example, the product S -> P | Q would be written as
    $S = \$T | \$Q;
where $S, $T and $Q are rules.

=head3 operator **

Using combinator. It takes a operator, combinator, compsite of combinators, product,
or reference to an instance of those classes as the left-hand-side operand and a
subroutine as the right-hand-side operand. The returned value of lhs operand will
be passed to rhs operand, and the returned value of rhs operand applied with its
argument will be returned. This combinator is used for semantic actions.
The returned value must be a reference to a list containing all the results given
by the semantic subroutine.

=head3 reference $many

Kleene star combinator. The argument combinator will be matched at least zero time.
The returned value is a list of all possible matchings.

=head2 Rules:

Rules are products. Products are compsite of operators and/or combinators. To create
a product, a scalar variable must be declared,
    my $P;
and then, call Wraith_rules->makerules(\$P) to make it a rule.

=head3 Wraith_rules->makerules( @list_of_references_to_products )

It takes a list of references to would-be rules and returned the blessed references.
However the returned values can be omitted for the contents of the variables are
already blessed. Thus, the variables are able to use the overloaded operators.

=head1 AUTHOR

Bo Wang <sceneviper@hotmail.com>

=head1 COPYRIGHT

Copyright 2013 - Bo Wang

=head1 SEE ALSO

Parser::Combinators, which implements parsec-like parser combinators.

=head1 LICENSE

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.
