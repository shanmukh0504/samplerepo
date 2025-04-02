import { createUser, showUser, Utils } from '@shanmukh0504/utils';

const user: Utils = createUser('0xE1CA48fcaFBD42Da402352b645A9855E33C716BE', 27000);

showUser(user);

export const getUserStatus = (user: Utils): string => {
    return user.exp < 1000 ? "User token will expire" : "User has a lot of time";
};