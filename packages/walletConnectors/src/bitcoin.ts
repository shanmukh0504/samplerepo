import { Utils } from '@shanmukh0504/utils';

export type Balance = {
    confirmed: number;
    unconfirmed: number;
    total: number;
};

export const createVehicle = (confirmed: number, unconfirmed: number, total: number): Balance => ({
    confirmed,
    unconfirmed,
    total
});

export const showBalance = (account: Balance) => console.log(`${account.confirmed} are confirmed and ${account.unconfirmed} are unconfirmed.`);
export const showUser = (user: Utils) => console.log(`User ${user.addr} will expire at ${user.exp}.`);