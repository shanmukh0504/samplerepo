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

export const showBalance = (account: Balance) => console.log(`${account.confirmed} are confirmed ${account.unconfirmed} are unconfirmed. But Total: ${account.total}`);
