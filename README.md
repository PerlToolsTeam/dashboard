# dashboard
Simple dashboard for monitoring CPAN modules

## Simple Set-Up

To configure this system to work with your system, do the following:

* Register with Coveralls using your Github login
* Activate the repos that you want to report on Coveralls
* Edit the `dashboard.json` file so it is configured correctly
* Push changes to your repos
* Run `dashboard`

**Note:** For (slightly) more detail about setting up Coveralls, see
[my presentation on the subject](http://www.slideshare.net/davorg/github-travisci-and-perl).


## Configuration

You configure the system by editing `dashboard.json`. There are two main sections in the file.

* **author** - information about the author of the modules.
  * **github** - your Github username.
  * **cpan** - your CPAN username.
* **output** - various output parameters
  * **file** - the name of the output file.
  * **template** - the name of the input template.
  * **title** - the title to use on the output page.
  * **menu** - a list of menu items to appear in header of the output page. Each item should be a JSON object with a **link** attribute and a **title** attribute.
  * **analytics** - a Google Analytics code. If this is given, then a Google Analytics section is added to the output.

## Example

You can see this code in action at https://cpandashboard.com/DAVECROSS/.
