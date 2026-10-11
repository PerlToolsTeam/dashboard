use Test::More;

use_ok($_) for qw[Dashboard::Author
                  Dashboard::BadgeMaker
                  Dashboard::App
                  VCS::Repository
                  Dashboard::GitHub
                  Dashboard::URL
                  Dashboard::BranchCache
                  Dashboard::Config];

done_testing();

