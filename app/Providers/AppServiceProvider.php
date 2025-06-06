<?php

namespace App\Providers;

use App\Models\UsefulLink;
use Exception;
use Illuminate\Pagination\Paginator;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\URL;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     *
     * @return void
     */
    public function register()
    {
        //
    }

    /**
     * Bootstrap any application services.
     *
     * @return void
     */
    public function boot()
    {
        Paginator::useBootstrap();
        Schema::defaultStringLength(191);

        Event::listen(function (\SocialiteProviders\Manager\SocialiteWasCalled $event) {
            $event->extendSocialite('discord', \SocialiteProviders\Discord\Provider::class);
        });

        Validator::extend('multiple_date_format', function ($attribute, $value, $parameters, $validator) {
            $ok = true;
            $result = [];

            foreach ($parameters as $parameter) {
                $result[] = $validator->validateDateFormat($attribute, $value, [$parameter]);
            }

            if (!in_array(true, $result)) {
                $ok = false;
                $validator->setCustomMessages(['multiple_date_format' => 'The format must be one of ' . implode(',', $parameters)]);
            }

            return $ok;
        });

        // Force HTTPS if APP_URL is set to https
        if (config('app.url') && parse_url(config('app.url'), PHP_URL_SCHEME) === 'https') {
            URL::forceScheme('https');
        }

        // 💣 Git branch seguro a prueba de todo
        try {
            $branchname = 'unknown';
            $gitHead = base_path('.git/HEAD');

            if (file_exists($gitHead)) {
                $contents = file($gitHead);
                if (isset($contents[0])) {
                    $exploded = explode('/', trim($contents[0]));
                    if (count($exploded) >= 3) {
                        $branchname = $exploded[2];
                    }
                }
            }
        } catch (Exception $e) {
            Log::notice("Failed to get Git branch: " . $e->getMessage());
            $branchname = 'unknown';
        }

        config(['BRANCHNAME' => $branchname]);

        // Do not run this code if no APP_KEY is set
        if (config('app.key') == null) return;

        try {
            if (Schema::hasColumn('useful_links', 'position')) {
                $useful_links = UsefulLink::where("position", "like", "%topbar%")->get()->sortBy("id");
                view()->share('useful_links', $useful_links);
            }
        } catch (Exception $e) {
            Log::error("Couldn't find useful_links. Probably the installation is not complete. " . $e);
        }
    }
}
