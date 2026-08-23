<?php

declare(strict_types=1);

namespace WebtreesMobileApi\Http\Handlers;

use Fisharebest\Webtrees\Auth;
use Fisharebest\Webtrees\Contracts\UserInterface;
use Fisharebest\Webtrees\Module\ModuleChartInterface;
use Fisharebest\Webtrees\Module\ModuleInterface;
use Fisharebest\Webtrees\Module\ModuleTabInterface;
use Fisharebest\Webtrees\Services\ModuleService;
use Fisharebest\Webtrees\Services\TreeService;
use Fisharebest\Webtrees\Tree;
use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\RequestHandlerInterface;
use WebtreesMobileApi\Http\Json;

/**
 * Who is signed in, and what they may do in each tree — in one request.
 *
 * This replaces the whole of the app's access probe: `4 + 3·N` requests for
 * `N` trees, each of them a page fetched only to be thrown away because a
 * *status code* was the answer. Worse, that ladder cannot state a role — it
 * infers one from which probe stopped refusing, and on a **public** tree it
 * cannot tell a Member from a Visitor at all, because webtrees serves them
 * the same routes. Here the role is simply asked for.
 *
 * `modules` matters as much as `role`. Which tabs and charts a site runs is
 * per tree and per user, no two instances agree, and a client that assumed
 * the core set would offer buttons for things this site does not have.
 */
final class Access implements RequestHandlerInterface
{
    public function __construct(
        private readonly TreeService $tree_service,
        private readonly ModuleService $module_service,
    ) {
    }

    public function handle(ServerRequestInterface $request): ResponseInterface
    {
        $user = Auth::user();

        $trees = [];

        // `all()` is already filtered: a private tree appears only for a user
        // whose role in it is not Visitor, which is the same rule that makes
        // an anonymous 404 prove a tree private.
        foreach ($this->tree_service->all() as $tree) {
            $trees[] = $this->tree($tree, $user);
        }

        return Json::ok([
            'account'         => [
                'username' => $user->userName(),
                'realName' => $user->realName(),
                'email'    => $user->email(),
            ],
            'isAdministrator' => Auth::isAdmin(),
            'trees'           => $trees,
        ]);
    }

    /**
     * @return array<string,mixed>
     */
    private function tree(Tree $tree, UserInterface $user): array
    {
        return [
            'name'    => $tree->name(),
            // Only ever on the tree's own page in HTML, and then only in the
            // default theme's `<h1 class="wt-site-title">`.
            'title'   => $tree->title(),
            'role'    => $this->role($tree, $user),
            'private' => $tree->private(),
            // webtrees uses this for relationship privacy, so a user usually
            // sees more of their own family than of anybody else's. The
            // account page renders the control disabled and empty, so on a
            // stock instance it has to be scraped from a menu link.
            'myXref'  => $this->myXref($tree, $user),
            'modules' => [
                'tabs'   => $this->names(ModuleTabInterface::class, $tree, $user),
                'charts' => $this->chartClasses($tree, $user),
            ],
        ];
    }

    /**
     * The role this user holds, stated rather than inferred.
     */
    private function role(Tree $tree, UserInterface $user): string
    {
        return match (true) {
            Auth::isAdmin($user)              => 'administrator',
            Auth::isManager($tree, $user)     => 'manager',
            Auth::isModerator($tree, $user)   => 'moderator',
            Auth::isEditor($tree, $user)      => 'editor',
            Auth::isMember($tree, $user)      => 'member',
            default                           => 'visitor',
        };
    }

    private function myXref(Tree $tree, UserInterface $user): string|null
    {
        $xref = $tree->getUserPreference($user, UserInterface::PREF_TREE_ACCOUNT_XREF);

        return $xref === '' ? null : $xref;
    }

    /**
     * @return array<string>
     */
    private function names(string $interface, Tree $tree, UserInterface $user): array
    {
        return $this->module_service
            ->findByComponent($interface, $tree, $user)
            ->map(static fn (ModuleInterface $module): string => $module->name())
            ->values()
            ->all();
    }

    /**
     * The charts this site runs, named by the CSS class webtrees puts on its
     * own links to them — `menu-chart-ancestry`.
     *
     * The same vocabulary in 2.2.x and 2.3, and the same vocabulary a client
     * already reads out of a rendered page, so a client that knows how to
     * discover charts from HTML needs no second dictionary for the module.
     *
     * @return array<string>
     */
    private function chartClasses(Tree $tree, UserInterface $user): array
    {
        return $this->module_service
            ->findByComponent(ModuleChartInterface::class, $tree, $user)
            ->map(static fn (ModuleChartInterface $module): string => $module->chartMenuClass())
            ->values()
            ->all();
    }
}
