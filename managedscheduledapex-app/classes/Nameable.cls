// Copyright Red Hat
// SPDX-License-Identifier: GPL-3.0-only
/**
 * This is an interface for simple assign a name to a class instance.
 * 
 * @version 2020-04-02
 * 
 * @author Bill Riemers <briemers@redhat.com>
 * @since 2020-04-02 US248556 - Created
 */
public interface Nameable {
    void setName(String value);
    String getName();
}