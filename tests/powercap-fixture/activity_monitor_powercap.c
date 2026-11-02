// SPDX-License-Identifier: GPL-2.0
/* VM-only powercap zone: exercises real sysfs attributes and udev events.
 * The synthetic energy rate is 10 W. This module never loads on the laptop.
 */
#include <linux/err.h>
#include <linux/ktime.h>
#include <linux/module.h>
#include <linux/powercap.h>

static struct powercap_control_type *control;
static struct powercap_zone *zone;

static int energy(struct powercap_zone *unused, u64 *value)
{
	*value = ktime_get_ns() / 100;
	return 0;
}

static int range(struct powercap_zone *unused, u64 *value)
{
	*value = U64_MAX >> 1;
	return 0;
}

static const struct powercap_zone_ops operations = {
	.get_energy_uj = energy,
	.get_max_energy_range_uj = range,
};

/* The framework validates these callbacks even with zero constraints. */
static int get_constraint(struct powercap_zone *unused, int index, u64 *value)
{
	return -EOPNOTSUPP;
}

static int set_constraint(struct powercap_zone *unused, int index, u64 value)
{
	return -EOPNOTSUPP;
}

static const struct powercap_zone_constraint_ops constraints = {
	.get_power_limit_uw = get_constraint,
	.set_power_limit_uw = set_constraint,
	.get_time_window_us = get_constraint,
	.set_time_window_us = set_constraint,
};

static int __init fixture_init(void)
{
	control = powercap_register_control_type(NULL, "intel-rapl-fixture", NULL);
	if (IS_ERR(control))
		return PTR_ERR(control);
	zone = powercap_register_zone(NULL, control, "package-fixture", NULL,
				     &operations, 0, &constraints);
	if (IS_ERR(zone)) {
		powercap_unregister_control_type(control);
		return PTR_ERR(zone);
	}
	return 0;
}

static void __exit fixture_exit(void)
{
	powercap_unregister_zone(control, zone);
	powercap_unregister_control_type(control);
}

module_init(fixture_init);
module_exit(fixture_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("VM-only synthetic powercap zone for permission regression tests");
