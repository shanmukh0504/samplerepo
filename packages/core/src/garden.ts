import { createUser, showUser, Utils } from '@shanmukh0504/utils';
import { getUserStatus } from '@shanmukh0504/orderbook';

export interface Garden {
    name: string;
    age: number;
}

const user: Utils = createUser('0xE1CA48fcaFBD42Da402352b645A9855E33C716BE', 2700);

const status = getUserStatus(user);

export const createGarden = (name: string, age: number): Garden => ({ name, age });

export const showGarden = (garden: Garden) => console.log(`${status} and ${garden.name} is ${garden.age} years old.`);
